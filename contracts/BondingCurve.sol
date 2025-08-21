// SPDX-License-Identifier: BUSL-1.1

// ███╗   ███╗ █████╗ ██╗  ██╗ █████╗
// ████╗ ████║██╔══██╗██║  ██║██╔══██╗
// ██╔████╔██║███████║███████║███████║
// ██║╚██╔╝██║██╔══██║██╔══██║██╔══██║
// ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██║
// ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝

// Website: https://maha.xyz
// Discord: https://discord.gg/mahadao
// Twitter: https://twitter.com/mahaxyz_

pragma solidity ^0.8.0;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


import {IBondingCurve} from "contracts/interfaces/IBondingCurve.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";

/// @notice Chainlink Price Feed Interface
interface IPriceOracle {
  function latestRoundData() external view returns (uint80 roundId, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
  function decimals() external view returns (uint8);
}

/// @title BondingCurve
/// @notice A contract that manages token pricing through bonding curves and handles DEX launches
/// @dev Uses constant product formula: (1e9 - supply) * (reserve + r) = r * 1e9
contract BondingCurve is IBondingCurve, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  // Constants
  uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1 billion tokens
  uint256 private constant _PRECISION = 1e18;
  uint256 private constant _PERCENTAGE_BASE = 10000; // 100% = 10000
  uint256 private constant _VIRTUAL_RESERVE = 0.5 ether; // Constant r = 0.5 ETH

  // Bonding curve configuration
  struct BondingCurveConfigInternal {
    IERC20 token;
    IERC20 fundingToken;
    ICLMMAdapter adapter;
    uint256 virtualReserve; // r value from bonding curve formula
    uint256 actualReserve; // current reserve balance (y in formula)
    uint256 circulatingSupply; // tokens in circulation (s in formula)
    bool isLaunched;
    bool burnPosition; 
    ITokenLaunchpad.ValueParams valueParams;
  }

  // State variables
  mapping(IERC20 => BondingCurveConfigInternal) public bondingCurves;
  mapping(IERC20 => bool) public isBondingCurveActive;
  
  // Protocol settings
  uint256 public protocolFee;
  address public feeDestination;
  ITokenLaunchpad public tokenLaunchpad;

  // Market cap-based launch settings
  mapping(IERC20 => address) public priceOracles; // Chainlink price feeds for funding tokens
  uint256 public launchMarketCapUSD; // Launch threshold in USD (e.g., $10,000)

  modifier onlyActiveBondingCurve(IERC20 _token) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    require(!bondingCurves[_token].isLaunched, "Token already launched");
    _;
  }

  /// @notice Initialize the bonding curve contract
  /// @param _owner The owner of the contract
  /// @param _tokenLaunchpad The token launchpad contract address
  /// @param _protocolFee The protocol fee (scaled by PERCENTAGE_BASE)
  /// @param _feeDestination The destination for protocol fees
  /// @param _launchMarketCapUSD The market cap threshold in USD for DEX launch
  function initialize(
    address _owner,
    address _tokenLaunchpad,
    uint256 _protocolFee,
    address _feeDestination,
    uint256 _launchMarketCapUSD
  ) external initializer {
    __Ownable_init(_owner);
    __ReentrancyGuard_init();
    
    tokenLaunchpad = ITokenLaunchpad(_tokenLaunchpad);
    protocolFee = _protocolFee;
    feeDestination = _feeDestination;
    launchMarketCapUSD = _launchMarketCapUSD; // e.g., 10_000e18 for $10,000
  }

  /// @inheritdoc IBondingCurve
  function createBondingCurve(
    IERC20 _token,
    IERC20 _fundingToken,
    ICLMMAdapter _adapter,
    bool _burnPosition,
    ITokenLaunchpad.ValueParams memory _valueParams
  ) external {
    require(msg.sender == address(tokenLaunchpad), "Only TokenLaunchpad can create");
    require(address(_token) != address(0), "Invalid token");
    require(address(_adapter) != address(0), "Invalid adapter");
    require(!isBondingCurveActive[_token], "Bonding curve already exists");

    bondingCurves[_token] = BondingCurveConfigInternal({
      token: _token,
      fundingToken: _fundingToken,
      adapter: _adapter,
      virtualReserve: _VIRTUAL_RESERVE, // Use constant r = 0.5 ETH
      actualReserve: 0, // y starts at 0
      circulatingSupply: 0, // s starts at 0 (all tokens locked)
      isLaunched: false,
      burnPosition: _burnPosition,
      valueParams: _valueParams
    });

    isBondingCurveActive[_token] = true;

    emit BondingCurveCreated(_token, _fundingToken, _getInitialPrice(_token));
  }

  /// @inheritdoc IBondingCurve
  function buyTokens(
    IERC20 _token,
    uint256 _amountIn,
    uint256 _minAmountOut
  ) external payable nonReentrant onlyActiveBondingCurve(_token) returns (uint256 amountOut) {
    require(_amountIn > 0, "Invalid amount");

    BondingCurveConfigInternal storage config = bondingCurves[_token];
    
    // Calculate new supply using bonding curve formula
    uint256 newReserve = config.actualReserve + _amountIn;
    uint256 newSupply = _estimateSupply(_VIRTUAL_RESERVE, newReserve);
    
    amountOut = newSupply - config.circulatingSupply;
    require(amountOut >= _minAmountOut, "Insufficient output amount");
    require(amountOut > 0, "No tokens to mint");
    require(newSupply <= TOTAL_SUPPLY, "Exceeds total supply");

    // Take protocol fee
    uint256 feeAmount = (_amountIn * protocolFee) / _PERCENTAGE_BASE;
    uint256 netAmountIn = _amountIn - feeAmount;

    if (address(config.fundingToken) == address(0)) {
      require(msg.value == _amountIn, "Incorrect ETH amount");
      if (feeAmount > 0) {
        payable(feeDestination).transfer(feeAmount);
      }
    } else {
      config.fundingToken.safeTransferFrom(msg.sender, address(this), _amountIn);
      if (feeAmount > 0) {
        config.fundingToken.safeTransfer(feeDestination, feeAmount);
      }
    }

    // Update state
    config.actualReserve += netAmountIn;
    config.circulatingSupply = newSupply;

    // Transfer tokens to user
    config.token.safeTransfer(msg.sender, amountOut);

    uint256 currentPrice = getCurrentPrice(_token);
    uint256 marketCap = getMarketCap(_token);
    
    emit TokensBought(msg.sender, _token, _amountIn, amountOut, currentPrice, marketCap);

    // Check for DEX migration (market cap threshold)
    if (_shouldMigrateToDEX(_token)) {
      _launchToDEX(_token);
    }

    return amountOut;
  }

  /// @inheritdoc IBondingCurve
  function sellTokens(
    IERC20 _token,
    uint256 _amountIn,
    uint256 _minAmountOut
  ) external nonReentrant onlyActiveBondingCurve(_token) returns (uint256 amountOut) {
    require(_amountIn > 0, "Invalid amount");

    BondingCurveConfigInternal storage config = bondingCurves[_token];
    require(_amountIn <= config.circulatingSupply, "Insufficient circulating supply");
    
    // Calculate new reserve using bonding curve formula
    uint256 newSupply = config.circulatingSupply - _amountIn;
    uint256 newReserve = _estimateReserve(_VIRTUAL_RESERVE, newSupply);
    
    amountOut = config.actualReserve - newReserve;
    require(amountOut >= _minAmountOut, "Insufficient output amount");
    require(config.actualReserve >= amountOut, "Insufficient reserves");

    // Take protocol fee
    uint256 feeAmount = (amountOut * protocolFee) / _PERCENTAGE_BASE;
    uint256 netAmountOut = amountOut - feeAmount;

    // Transfer tokens from user
    config.token.safeTransferFrom(msg.sender, address(this), _amountIn);

    // Update state
    config.actualReserve = newReserve;
    config.circulatingSupply = newSupply;

    // Transfer funding tokens to user
    if (address(config.fundingToken) == address(0)) {
      payable(msg.sender).transfer(netAmountOut);
      if (feeAmount > 0) {
        payable(feeDestination).transfer(feeAmount);
      }
    } else {
      config.fundingToken.safeTransfer(msg.sender, netAmountOut);
      if (feeAmount > 0) {
        config.fundingToken.safeTransfer(feeDestination, feeAmount);
      }
    }

    uint256 currentPrice = getCurrentPrice(_token);
    uint256 marketCap = getMarketCap(_token);
    
    emit TokensSold(msg.sender, _token, _amountIn, amountOut, currentPrice, marketCap);

    return netAmountOut;
  }

  /// @inheritdoc IBondingCurve
  function getBuyPrice(IERC20 _token, uint256 _amountIn) external view returns (uint256 amountOut) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    uint256 newReserve = config.actualReserve + _amountIn;
    uint256 newSupply = _estimateSupply(_VIRTUAL_RESERVE, newReserve);
    return newSupply - config.circulatingSupply;
  }

  /// @inheritdoc IBondingCurve
  function getSellPrice(IERC20 _token, uint256 _amountIn) external view returns (uint256 amountOut) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    if (_amountIn > config.circulatingSupply) return 0;
    
    uint256 newSupply = config.circulatingSupply - _amountIn;
    uint256 newReserve = _estimateReserve(_VIRTUAL_RESERVE, newSupply);
    return config.actualReserve - newReserve;
  }

  /// @notice Get current token price using bonding curve formula
  /// @param _token The token to get price for
  /// @return price Current price per token
  function getCurrentPrice(IERC20 _token) public view returns (uint256 price) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    return _getPrice(_VIRTUAL_RESERVE, config.circulatingSupply);
  }

  /// @inheritdoc IBondingCurve
  function getMarketCap(IERC20 _token) public view returns (uint256 marketCap) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    uint256 price = getCurrentPrice(_token);
    return (price * config.circulatingSupply) / _PRECISION;
  }

  /// @inheritdoc IBondingCurve
  function setMarketCapThresholds(MarketCapThreshold[] memory /* _thresholds */) external onlyOwner {
    // This implementation uses simple 80% supply threshold, not market cap thresholds
    // Function kept for interface compatibility
  }

  /// @inheritdoc IBondingCurve
  function getSupplyAllocation(uint256 /* _marketCapUSD */) public pure returns (uint256 supplyPercentage) {
    // Always uses 80% allocation
    return 8000; // 80%
  }

  /// @dev Check if token should migrate to DEX (market cap threshold)
  function _shouldMigrateToDEX(IERC20 _token) internal view returns (bool) {
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    // Get actual reserves collected (ETH/WBNB amount)
    uint256 reservesInFundingToken = config.actualReserve;
    
    // Convert reserves to USD using price oracle
    uint256 reservesUSD = _convertToUSD(config.fundingToken, reservesInFundingToken);
    
    // Check if reserves exceed threshold ($10,000)
    return reservesUSD >= launchMarketCapUSD;
  }

  /// @dev Convert funding token amount to USD using price oracle
  function _convertToUSD(IERC20 _fundingToken, uint256 _amount) internal view returns (uint256) {
    address oracle = priceOracles[_fundingToken];
    
    if (oracle == address(0)) {
      // No oracle set, assume 1:1 with USD (for stablecoins like USDC)
      return _amount;
    }
    
    // Get price from Chainlink oracle
    (, int256 price, , , ) = IPriceOracle(oracle).latestRoundData();
    uint8 decimals = IPriceOracle(oracle).decimals();
    
    require(price > 0, "Invalid oracle price");
    
    // Convert: amount * price / 10^decimals
    return (_amount * uint256(price)) / (10 ** decimals);
  }

  /// @dev Get market cap in USD using actual reserves
  function _getMarketCapInUSD(IERC20 _token) internal view returns (uint256) {
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    // Market cap = actual reserves collected in USD
    return _convertToUSD(config.fundingToken, config.actualReserve);
  }

  /// @inheritdoc IBondingCurve
  function shouldLaunchToDEX(IERC20 _token) public view returns (bool shouldLaunch) {
    if (!isBondingCurveActive[_token] || bondingCurves[_token].isLaunched) {
      return false;
    }
    return _shouldMigrateToDEX(_token);
  }

  /// @inheritdoc IBondingCurve
  function launchToDEX(IERC20 _token) external nonReentrant returns (address pool) {
    require(shouldLaunchToDEX(_token), "Token not ready for launch");
    return _launchToDEX(_token);
  }

  /// @inheritdoc IBondingCurve
  function getBondingCurveConfig(IERC20 _token) external view returns (BondingCurveConfig memory config) {
    BondingCurveConfigInternal memory internalConfig = bondingCurves[_token];
    return BondingCurveConfig({
      token: internalConfig.token,
      fundingToken: internalConfig.fundingToken,
      adapter: internalConfig.adapter,
      totalSupply: TOTAL_SUPPLY,
      reserveBalance: internalConfig.actualReserve,
      currentPrice: getCurrentPrice(_token),
      k: _VIRTUAL_RESERVE,
      isLaunched: internalConfig.isLaunched,
      valueParams: internalConfig.valueParams
    });
  }

  /// @inheritdoc IBondingCurve
  function getMarketCapThresholds() external pure returns (MarketCapThreshold[] memory thresholds) {
    // This implementation doesn't use market cap thresholds, return empty array
    return new MarketCapThreshold[](0);
  }

  /// @notice Set protocol settings
  /// @param _protocolFee The new protocol fee
  /// @param _feeDestination The new fee destination
  function setProtocolSettings(uint256 _protocolFee, address _feeDestination) external onlyOwner {
    require(_protocolFee <= 1000, "Fee too high"); // Max 10%
    require(_feeDestination != address(0), "Invalid fee destination");
    
    protocolFee = _protocolFee;
    feeDestination = _feeDestination;
  }



  /// @notice Emergency function to disable a bonding curve
  /// @param _token The token to disable bonding curve for
  function disableBondingCurve(IERC20 _token) external onlyOwner {
    isBondingCurveActive[_token] = false;
  }

  /// @dev Estimate supply given reserve using bonding curve formula
  /// @dev Mathematical Formula: (TOTAL_SUPPLY - supply) * (reserve + r) = r * TOTAL_SUPPLY
  /// @dev Solving for supply: supply = TOTAL_SUPPLY - (r * TOTAL_SUPPLY) / (reserve + r)
  /// @dev This calculates how many tokens should be in circulation for a given reserve amount
  /// @param r Virtual reserve parameter (constant 0.5 ETH)
  /// @param reserve Actual reserve amount (ETH/WBNB collected)
  /// @return supply Estimated circulating supply
  function _estimateSupply(uint256 r, uint256 reserve) internal pure returns (uint256 supply) {
    // Avoid division by zero
    if (reserve + r == 0) return 0;
    
    // Mathematical Formula: supply = TOTAL_SUPPLY - (r * TOTAL_SUPPLY) / (reserve + r)
    // Example: reserve = 1 ETH, r = 0.5 ETH
    // supply = 1e9 - (0.5 * 1e9) / (1 + 0.5) = 1e9 - 5e8/1.5 = 1e9 - 333M = 667M tokens
    uint256 nonCirculating = (r * TOTAL_SUPPLY) / (reserve + r);
    
    if (nonCirculating >= TOTAL_SUPPLY) return 0;
    return TOTAL_SUPPLY - nonCirculating;
  }

  /// @dev Estimate reserve given supply using bonding curve formula
  /// @dev Formula: (1e9 - supply) * (reserve + r) = r * 1e9
  /// @dev Solving for reserve: reserve = (r * 1e9) / (1e9 - supply) - r
  /// @param r Virtual reserve parameter
  /// @param supply Circulating supply
  /// @return reserve Estimated reserve amount
  function _estimateReserve(uint256 r, uint256 supply) internal pure returns (uint256 reserve) {
    if (supply >= TOTAL_SUPPLY) return type(uint256).max;
    
    uint256 nonCirculating = TOTAL_SUPPLY - supply;
    
    // Formula: reserve = (r * TOTAL_SUPPLY) / nonCirculating - r
    uint256 totalReserve = (r * TOTAL_SUPPLY) / nonCirculating;
    
    if (totalReserve <= r) return 0;
    return totalReserve - r;
  }

  /// @dev Get price using bonding curve formula
  /// @dev Mathematical Formula: price = (r * TOTAL_SUPPLY * PRECISION) / (TOTAL_SUPPLY - supply)²
  /// @dev Where r = 0.5 ETH (virtual reserve), supply = circulating tokens
  /// @dev As supply increases → remaining decreases → price increases exponentially
  /// @param r Virtual reserve parameter (constant 0.5 ETH)
  /// @param supply Current circulating supply
  /// @return price Price per token in funding token (ETH/WBNB)
  function _getPrice(uint256 r, uint256 supply) internal pure returns (uint256 price) {
    if (supply >= TOTAL_SUPPLY) return type(uint256).max;
    
    uint256 remaining = TOTAL_SUPPLY - supply;
    
    // Mathematical Formula: price = (r * TOTAL_SUPPLY * 1e18) / (remaining_supply)²
    // Example: When supply = 0, price = (0.5 * 1e9 * 1e18) / (1e9)² = 0.5 wei per token
    // Example: When supply = 500M, price = (0.5 * 1e9 * 1e18) / (500M)² = 2 wei per token
    return (r * TOTAL_SUPPLY * _PRECISION) / (remaining * remaining);
  }



  /// @dev Get initial price (when supply = 0)
  function _getInitialPrice(IERC20 /* _token */) internal pure returns (uint256) {
    return _getPrice(_VIRTUAL_RESERVE, 0);
  }

  /// @notice Calculate tokens received for first purchase (demonstration)
  /// @param _amountIn The amount of funding tokens to spend
  /// @return tokensOut The amount of tokens that would be received
  function calculateFirstPurchase(uint256 _amountIn) external pure returns (uint256 tokensOut) {
    // Starting from 0 supply and 0 reserve
    uint256 newSupply = _estimateSupply(_VIRTUAL_RESERVE, _amountIn);
    return newSupply; // Since starting supply is 0
  }

  /// @notice Get the exact initial price for any token
  /// @return initialPrice The initial price per token
  function getInitialPrice() external pure returns (uint256 initialPrice) {
    return _getPrice(_VIRTUAL_RESERVE, 0);
  }

  /// @dev Launch token to DEX
  function _launchToDEX(IERC20 _token) internal returns (address pool) {
    BondingCurveConfigInternal storage config = bondingCurves[_token];
    require(!config.isLaunched, "Already launched");
    
    // Calculate remaining tokens and reserves for DEX
    uint256 remainingTokens = TOTAL_SUPPLY - config.circulatingSupply;
    uint256 remainingReserve = config.actualReserve;
    
    // Mark as launched
    config.isLaunched = true;
    
    // Add liquidity to DEX through adapter (like original TokenLaunchpad)
    config.token.approve(address(config.adapter), type(uint256).max);
    config.fundingToken.approve(address(config.adapter), type(uint256).max);
    
    // Use adapter to add single-sided liquidity
    // Ensure graduationAmount doesn't exceed available tokens
    uint256 graduationAmount = (remainingTokens * 80) / 100;
    
    pool = config.adapter.addSingleSidedLiquidity(
      ICLMMAdapter.AddLiquidityParams({
        tokenBase: config.token,
        tokenQuote: config.fundingToken,
        tick0: config.valueParams.launchTick,
        tick1: config.valueParams.graduationTick,
        tick2: config.valueParams.upperMaxTick,
        fee: config.valueParams.fee,
        tickSpacing: config.valueParams.tickSpacing,
        totalAmount: remainingTokens,
        graduationAmount: graduationAmount,
        burnPosition: config.burnPosition
      })
    );

    // Add initial trading activity to register token on tools like DexScreener
    config.fundingToken.approve(address(config.adapter), type(uint256).max);
    
    // Buy a small amount of tokens to register the token on tools like dexscreener
    uint256 balance = config.fundingToken.balanceOf(address(this));
    
    // Buy 1 token if we have remaining balance
    if (balance > 0) {
      config.adapter.swapWithExactOutput(config.fundingToken, config.token, 1 ether, balance, config.valueParams.fee);
    }
    
    uint256 marketCapUSD = _getMarketCapInUSD(_token);
    emit TokenLaunchedToDEX(_token, pool, remainingTokens, remainingReserve, marketCapUSD);
    
    return pool;
  }

  /// @notice Set price oracle for a funding token
  /// @param _fundingToken The funding token (e.g., WETH, WBNB)
  /// @param _oracle The Chainlink price feed address (e.g., ETH/USD, BNB/USD)
  function setPriceOracle(IERC20 _fundingToken, address _oracle) external onlyOwner {
    require(_oracle != address(0), "Invalid oracle address");
    priceOracles[_fundingToken] = _oracle;
  }

  /// @notice Set launch market cap threshold in USD
  /// @param _launchMarketCapUSD The market cap threshold (e.g., 10_000e18 for $10,000)
  function setLaunchMarketCapUSD(uint256 _launchMarketCapUSD) external onlyOwner {
    require(_launchMarketCapUSD > 0, "Invalid market cap threshold");
    launchMarketCapUSD = _launchMarketCapUSD;
  }

  /// @notice Get current market cap in USD
  /// @param _token The token to get market cap for
  /// @return marketCapUSD The market cap in USD
  function getMarketCapUSD(IERC20 _token) external view returns (uint256 marketCapUSD) {
    return _getMarketCapInUSD(_token);
  }

  // Emergency functions
  receive() external payable {}
  
  function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
    if (token == address(0)) {
      payable(owner()).transfer(amount);
    } else {
      IERC20(token).safeTransfer(owner(), amount);
    }
  }
}
