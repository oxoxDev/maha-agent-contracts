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

/// @title BondingCurve
/// @notice A contract that manages token pricing through bonding curves and handles DEX launches
/// @dev Uses constant product formula: (1e9 - supply) * (reserve + r) = r * 1e9
contract BondingCurve is IBondingCurve, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  // Constants
  uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether; // 1 billion tokens
  uint256 private constant PRECISION = 1e18;
  uint256 private constant PERCENTAGE_BASE = 10000; // 100% = 10000
  uint256 private constant MIGRATION_THRESHOLD_PERCENT = 80; // 80% for DEX migration

  // Bonding curve configuration
  struct BondingCurveConfigInternal {
    IERC20 token;
    IERC20 fundingToken;
    ICLMMAdapter adapter;
    uint256 virtualReserve; // r value from bonding curve formula
    uint256 actualReserve; // current reserve balance (y in formula)
    uint256 circulatingSupply; // tokens in circulation (s in formula)
    uint256 launchMarketCap; // market cap threshold for DEX launch
    bool isLaunched;
    ITokenLaunchpad.ValueParams valueParams;
  }

  // State variables
  mapping(IERC20 => BondingCurveConfigInternal) public bondingCurves;
  mapping(IERC20 => bool) public isBondingCurveActive;
  
  // Protocol settings
  uint256 public protocolFee;
  address public feeDestination;
  ITokenLaunchpad public tokenLaunchpad;

  // Special token addresses for determining r values
  address public specialTokenAddress;

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
  /// @param _specialToken The special token address for r value determination
  function initialize(
    address _owner,
    address _tokenLaunchpad,
    uint256 _protocolFee,
    address _feeDestination,
    address _specialToken
  ) external initializer {
    __Ownable_init(_owner);
    __ReentrancyGuard_init();
    
    tokenLaunchpad = ITokenLaunchpad(_tokenLaunchpad);
    protocolFee = _protocolFee;
    feeDestination = _feeDestination;
    specialTokenAddress = _specialToken;
  }

  /// @inheritdoc IBondingCurve
  function createBondingCurve(
    IERC20 _token,
    IERC20 _fundingToken,
    ICLMMAdapter _adapter,
    uint256 _launchMarketCap,
    ITokenLaunchpad.ValueParams memory _valueParams
  ) external {
    require(msg.sender == address(tokenLaunchpad), "Only TokenLaunchpad can create");
    require(address(_token) != address(0), "Invalid token");
    require(address(_adapter) != address(0), "Invalid adapter");
    require(_launchMarketCap > 0, "Invalid launch market cap");
    require(!isBondingCurveActive[_token], "Bonding curve already exists");

    // Determine virtual reserve (r value) based on funding token
    uint256 virtualReserve = _getVirtualReserve(_fundingToken);

    bondingCurves[_token] = BondingCurveConfigInternal({
      token: _token,
      fundingToken: _fundingToken,
      adapter: _adapter,
      virtualReserve: virtualReserve,
      actualReserve: 0, // y starts at 0
      circulatingSupply: 0, // s starts at 0 (all tokens locked)
      launchMarketCap: _launchMarketCap,
      isLaunched: false,
      valueParams: _valueParams
    });

    isBondingCurveActive[_token] = true;

    emit BondingCurveCreated(_token, _fundingToken, _getInitialPrice(_token), _launchMarketCap);
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
    uint256 newSupply = _estimateSupply(config.virtualReserve, newReserve);
    
    amountOut = newSupply - config.circulatingSupply;
    require(amountOut >= _minAmountOut, "Insufficient output amount");
    require(amountOut > 0, "No tokens to mint");
    require(newSupply <= TOTAL_SUPPLY, "Exceeds total supply");

    // Take protocol fee
    uint256 feeAmount = (_amountIn * protocolFee) / PERCENTAGE_BASE;
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

    // Check for DEX migration (80% threshold)
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
    uint256 newReserve = _estimateReserve(config.virtualReserve, newSupply);
    
    amountOut = config.actualReserve - newReserve;
    require(amountOut >= _minAmountOut, "Insufficient output amount");
    require(config.actualReserve >= amountOut, "Insufficient reserves");

    // Take protocol fee
    uint256 feeAmount = (amountOut * protocolFee) / PERCENTAGE_BASE;
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
    uint256 newSupply = _estimateSupply(config.virtualReserve, newReserve);
    return newSupply - config.circulatingSupply;
  }

  /// @inheritdoc IBondingCurve
  function getSellPrice(IERC20 _token, uint256 _amountIn) external view returns (uint256 amountOut) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    if (_amountIn > config.circulatingSupply) return 0;
    
    uint256 newSupply = config.circulatingSupply - _amountIn;
    uint256 newReserve = _estimateReserve(config.virtualReserve, newSupply);
    return config.actualReserve - newReserve;
  }

  /// @notice Get current token price using bonding curve formula
  /// @param _token The token to get price for
  /// @return price Current price per token
  function getCurrentPrice(IERC20 _token) public view returns (uint256 price) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    
    return _getPrice(config.virtualReserve, config.circulatingSupply);
  }

  /// @inheritdoc IBondingCurve
  function getMarketCap(IERC20 _token) public view returns (uint256 marketCap) {
    require(isBondingCurveActive[_token], "Bonding curve not active");
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    uint256 price = getCurrentPrice(_token);
    return (price * config.circulatingSupply) / PRECISION;
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

  /// @dev Check if token should migrate to DEX (80% threshold)
  function _shouldMigrateToDEX(IERC20 _token) internal view returns (bool) {
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    uint256 supplyPercentage = (config.circulatingSupply * 100) / TOTAL_SUPPLY;
    return supplyPercentage >= MIGRATION_THRESHOLD_PERCENT;
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
      k: internalConfig.virtualReserve,
      isLaunched: internalConfig.isLaunched,
      launchMarketCap: internalConfig.launchMarketCap,
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
  /// @dev Formula: (1e9 - supply) * (reserve + r) = r * 1e9
  /// @dev Solving for supply: supply = 1e9 - (r * 1e9) / (reserve + r)
  /// @param r Virtual reserve parameter
  /// @param reserve Actual reserve amount
  /// @return supply Estimated circulating supply
  function _estimateSupply(uint256 r, uint256 reserve) internal pure returns (uint256 supply) {
    // Avoid division by zero
    if (reserve + r == 0) return 0;
    
    // Formula: supply = TOTAL_SUPPLY - (r * TOTAL_SUPPLY) / (reserve + r)
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
  /// @dev Formula: price = r * 1e9 / (1e9 - supply)^2
  /// @param r Virtual reserve parameter
  /// @param supply Current circulating supply
  /// @return price Price per token
  function _getPrice(uint256 r, uint256 supply) internal pure returns (uint256 price) {
    if (supply >= TOTAL_SUPPLY) return type(uint256).max;
    
    uint256 remaining = TOTAL_SUPPLY - supply;
    
    // Formula: price = (r * TOTAL_SUPPLY) / (remaining^2)
    return (r * TOTAL_SUPPLY * PRECISION) / (remaining * remaining);
  }

  /// @dev Get virtual reserve (r value) based on funding token
  function _getVirtualReserve(IERC20 _fundingToken) internal view returns (uint256) {
    if (address(_fundingToken) == address(0)) {
      return 0.5 ether; // ETH uses r = 0.5
    } else if (address(_fundingToken) == specialTokenAddress) {
      return 4_000_000 ether; // Special token uses r = 4,000,000
    } else {
      return 0.5 ether; // Default to ETH curve
    }
  }

  /// @dev Get initial price (when supply = 0)
  function _getInitialPrice(IERC20 _token) internal view returns (uint256) {
    BondingCurveConfigInternal memory config = bondingCurves[_token];
    return _getPrice(config.virtualReserve, 0);
  }

  /// @notice Calculate tokens received for first ETH purchase (demonstration)
  /// @param _fundingToken The funding token to use
  /// @param _amountIn The amount of funding tokens to spend
  /// @return tokensOut The amount of tokens that would be received
  function calculateFirstPurchase(IERC20 _fundingToken, uint256 _amountIn) external view returns (uint256 tokensOut) {
    uint256 r = _getVirtualReserve(_fundingToken);
    
    // Starting from 0 supply and 0 reserve
    uint256 newSupply = _estimateSupply(r, _amountIn);
    return newSupply; // Since starting supply is 0
  }

  /// @notice Get the exact initial price for a funding token
  /// @param _fundingToken The funding token
  /// @return initialPrice The initial price per token
  function getInitialPriceForToken(IERC20 _fundingToken) external view returns (uint256 initialPrice) {
    uint256 r = _getVirtualReserve(_fundingToken);
    return _getPrice(r, 0);
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
        graduationAmount: config.valueParams.graduationLiquidity,
        burnPosition: true
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

  /// @dev Get market cap in USD
  function _getMarketCapInUSD(IERC20 _token) internal view returns (uint256) {
    // Return the market cap in funding token
    return getMarketCap(_token);
  }

  function setSpecialToken(address _specialToken) external onlyOwner {
    require(_specialToken != address(0), "Invalid special token");
    specialTokenAddress = _specialToken;
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
