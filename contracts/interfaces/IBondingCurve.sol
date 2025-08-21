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

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLMMAdapter} from "./ICLMMAdapter.sol";
import {ITokenLaunchpad} from "./ITokenLaunchpad.sol";

/// @title IBondingCurve Interface
/// @notice Interface for the BondingCurve contract that handles token pricing and liquidity distribution
interface IBondingCurve {
  /// @notice Market cap threshold configuration for supply allocation
  struct MarketCapThreshold {
    uint256 marketCapUSD; // Market cap threshold in USD (scaled by 1e18)
    uint256 supplyPercentage; // Percentage of supply to allocate to DEX (scaled by 10000, e.g., 8000 = 80%)
    bool isActive; // Whether this threshold is active
  }

  /// @notice Token bonding curve configuration
  struct BondingCurveConfig {
    IERC20 token; // The token being managed
    IERC20 fundingToken; // The token used for funding (e.g., WETH, USDC)
    ICLMMAdapter adapter; // The adapter for liquidity management
    uint256 totalSupply; // Total token supply
    uint256 reserveBalance; // Current reserve balance in funding token
    uint256 currentPrice; // Current price per token in funding token
    uint256 k; // Bonding curve constant (for price calculation)
    bool isLaunched; // Whether the token has been launched to DEX
    ITokenLaunchpad.ValueParams valueParams; // Parameters for DEX launch
  }

  /// @notice Emitted when a token's bonding curve is created
  /// @param token The token address
  /// @param fundingToken The funding token address
  /// @param initialPrice The initial price per token
  event BondingCurveCreated(
    IERC20 indexed token,
    IERC20 indexed fundingToken,
    uint256 initialPrice
  );

  /// @notice Emitted when tokens are bought on the bonding curve
  /// @param buyer The buyer address
  /// @param token The token address
  /// @param amountIn The amount of funding tokens spent
  /// @param amountOut The amount of tokens received
  /// @param newPrice The new price per token
  /// @param marketCap The current market cap
  event TokensBought(
    address indexed buyer,
    IERC20 indexed token,
    uint256 amountIn,
    uint256 amountOut,
    uint256 newPrice,
    uint256 marketCap
  );

  /// @notice Emitted when tokens are sold on the bonding curve
  /// @param seller The seller address
  /// @param token The token address
  /// @param amountIn The amount of tokens sold
  /// @param amountOut The amount of funding tokens received
  /// @param newPrice The new price per token
  /// @param marketCap The current market cap
  event TokensSold(
    address indexed seller,
    IERC20 indexed token,
    uint256 amountIn,
    uint256 amountOut,
    uint256 newPrice,
    uint256 marketCap
  );

  /// @notice Emitted when a token is launched to DEX
  /// @param token The token address
  /// @param pool The DEX pool address
  /// @param supplyAllocated The amount of supply allocated to DEX
  /// @param reserveAllocated The amount of reserves allocated to DEX
  /// @param finalMarketCap The final market cap at launch
  event TokenLaunchedToDEX(
    IERC20 indexed token,
    address indexed pool,
    uint256 supplyAllocated,
    uint256 reserveAllocated,
    uint256 finalMarketCap
  );

  /// @notice Emitted when market cap thresholds are updated
  /// @param marketCapUSD The market cap threshold
  /// @param supplyPercentage The supply percentage for this threshold
  /// @param isActive Whether the threshold is active
  event MarketCapThresholdUpdated(uint256 marketCapUSD, uint256 supplyPercentage, bool isActive);

  /// @notice Creates a new bonding curve for a token
  /// @param _token The token to create a bonding curve for
  /// @param _fundingToken The funding token (e.g., WETH, USDC)
  /// @param _adapter The CLMM adapter for DEX integration
  /// @param _valueParams The parameters for DEX launch
  /// @dev Initial price is auto-calculated from bonding curve formula: r / 10^9
  function createBondingCurve(
    IERC20 _token,
    IERC20 _fundingToken,
    ICLMMAdapter _adapter,
    ITokenLaunchpad.ValueParams memory _valueParams
  ) external;

  /// @notice Buy tokens on the bonding curve
  /// @param _token The token to buy
  /// @param _amountIn The amount of funding tokens to spend
  /// @param _minAmountOut The minimum amount of tokens to receive
  /// @return amountOut The amount of tokens received
  function buyTokens(IERC20 _token, uint256 _amountIn, uint256 _minAmountOut) external payable returns (uint256 amountOut);

  /// @notice Sell tokens on the bonding curve
  /// @param _token The token to sell
  /// @param _amountIn The amount of tokens to sell
  /// @param _minAmountOut The minimum amount of funding tokens to receive
  /// @return amountOut The amount of funding tokens received
  function sellTokens(IERC20 _token, uint256 _amountIn, uint256 _minAmountOut) external returns (uint256 amountOut);

  /// @notice Get the current price for buying tokens
  /// @param _token The token to get the price for
  /// @param _amountIn The amount of funding tokens to spend
  /// @return amountOut The amount of tokens that would be received
  function getBuyPrice(IERC20 _token, uint256 _amountIn) external view returns (uint256 amountOut);

  /// @notice Get the current price for selling tokens
  /// @param _token The token to get the price for
  /// @param _amountIn The amount of tokens to sell
  /// @return amountOut The amount of funding tokens that would be received
  function getSellPrice(IERC20 _token, uint256 _amountIn) external view returns (uint256 amountOut);

  /// @notice Get the current market cap of a token
  /// @param _token The token to get the market cap for
  /// @return marketCap The current market cap in funding token
  function getMarketCap(IERC20 _token) external view returns (uint256 marketCap);

  /// @notice Set market cap thresholds for supply allocation
  /// @param _thresholds Array of market cap thresholds
  function setMarketCapThresholds(MarketCapThreshold[] memory _thresholds) external;

  /// @notice Get the supply allocation percentage for a given market cap
  /// @param _marketCapUSD The market cap in USD
  /// @return supplyPercentage The percentage of supply to allocate to DEX
  function getSupplyAllocation(uint256 _marketCapUSD) external view returns (uint256 supplyPercentage);

  /// @notice Check if a token should be launched to DEX
  /// @param _token The token to check
  /// @return shouldLaunch Whether the token should be launched
  function shouldLaunchToDEX(IERC20 _token) external view returns (bool shouldLaunch);

  /// @notice Launch a token to DEX when threshold is reached
  /// @param _token The token to launch
  /// @return pool The address of the created DEX pool
  function launchToDEX(IERC20 _token) external returns (address pool);

  /// @notice Get bonding curve configuration for a token
  /// @param _token The token to get configuration for
  /// @return config The bonding curve configuration
  function getBondingCurveConfig(IERC20 _token) external view returns (BondingCurveConfig memory config);

  /// @notice Get all active market cap thresholds
  /// @return thresholds Array of active market cap thresholds
  function getMarketCapThresholds() external view returns (MarketCapThreshold[] memory thresholds);
}
