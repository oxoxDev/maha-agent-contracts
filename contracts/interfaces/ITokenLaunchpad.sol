// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ICLMMAdapter} from "./ICLMMAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ITokenLaunchpad Interface
/// @notice Interface for the TokenLaunchpad contract that handles token launches
interface ITokenLaunchpad {
  /// @notice Parameters required to create a new token launch
  /// @param name The name of the token
  /// @param symbol The symbol of the token
  /// @param metadata IPFS hash or other metadata about the token
  /// @param fundingToken The token used for funding the launch
  /// @param salt Random value to ensure unique deployment address
  /// @param launchTick The tick at which the token launches
  /// @param graduationTick The tick that must be reached for graduation
  /// @param upperMaxTick The maximum tick allowed
  /// @param graduationLiquidity The liquidity at graduation
  /// @param fee The fee for the token liquidity pair
  /// @param adapter The adapter used for the token launch
  struct CreateParams {
    bytes32 salt;
    ICLMMAdapter adapter;
    IERC20 fundingToken;
    string metadata;
    string name;
    string symbol;
    uint256[] launchPoolAmounts;
    ValueParams valueParams;
  }

  // Contains numeric launch parameters
  struct ValueParams {
    int24 launchTick;
    int24 graduationTick;
    int24 upperMaxTick;
    uint24 fee;
    int24 tickSpacing;
    uint256 graduationLiquidity;
  }

  /// @notice Emitted when fee settings are updated
  /// @param feeDestination The address where fees will be sent
  /// @param fee The new fee amount
  event FeeUpdated(address indexed feeDestination, uint256 fee);

  /// @notice Emitted when a token is launched
  /// @param token The token that was launched
  /// @param adapter The address of the adapter used to launch the token
  /// @param pool The address of the pool for the token
  /// @param params The parameters used to launch the token
  event TokenLaunched(IERC20 indexed token, address indexed adapter, address indexed pool, CreateParams params);

  /// @notice Emitted when referral settings are updated
  /// @param referralDestination The address where referrals will be sent
  /// @param referralFee The new referral fee amount
  event ReferralUpdated(address indexed referralDestination, uint256 referralFee);

  /// @notice Emitted when tokens are allocated to the creator
  /// @param token The token that was launched
  /// @param creator The address of the creator
  /// @param amount The amount of tokens allocated to the creator
  event CreatorAllocation(IERC20 indexed token, address indexed creator, uint256 amount);

  /// @notice Emitted when an adapter is set
  /// @param _adapter The adapter address
  /// @param _enabled Whether the adapter is enabled
  event AdapterSet(address indexed _adapter, bool _enabled);

  /// @notice Emitted when a whitelist is updated
  /// @param _address The address that was updated
  /// @param _whitelisted Whether the address is whitelisted
  event WhitelistUpdated(address indexed _address, bool _whitelisted);

  /// @notice Emitted when the cron is updated
  /// @param newCron The new cron address
  event CronUpdated(address indexed newCron);

  /// @notice Emitted when the metadata URL is updated
  /// @param metadataUrl The new metadata URL
  event MetadataUrlUpdated(string metadataUrl);

  /// @notice Emitted when the default creator allocation is updated
  /// @param _creatorAllocation The new default creator allocation percentage
  event DefaultCreatorAllocationSet(uint256 _creatorAllocation);

  /// @notice Emitted when the airdrop rewarder is set
  /// @param _airdropRewarder The address of the airdrop rewarder
  event AirdropRewarderSet(address indexed _airdropRewarder);

  /// @notice Emitted when a fee is claimed for a token
  /// @param _token The token that the fee was claimed for
  /// @param _fee0 The amount of fee claimed for token0
  /// @param _fee1 The amount of fee claimed for token1
  event FeeClaimed(IERC20 indexed _token, uint256 _fee0, uint256 _fee1);

  /// @notice Initializes the launchpad contract
  /// @param _owner The owner address
  /// @param _weth The WETH9 contract address
  function initialize(address _owner, address _weth) external;

  /// @notice Toggles the whitelist for an address
  /// @param _address The address to toggle the whitelist for
  function toggleWhitelist(address _address) external;

  /// @notice Sets the value parameters for a token
  /// @param _token The token to set the value parameters for
  /// @param _adapter The adapter to set the value parameters for
  /// @param _params The value parameters to set
  function setDefaultValueParams(IERC20 _token, ICLMMAdapter _adapter, ValueParams memory _params) external;

  /// @notice Sets the cron address
  /// @param _cron The new cron address
  function setCron(address _cron) external;

  /// @notice Sets the default creator allocation
  /// @param _creatorAllocation The new default creator allocation percentage
  function setDefaultCreatorAllocation(uint16 _creatorAllocation) external;

  /// @notice Gets the quote token for a token
  /// @param _token The token to get the quote token for
  /// @return quoteToken The quote token for the token
  function getQuoteToken(IERC20 _token) external view returns (IERC20 quoteToken);

  /// @notice Gets the value parameters for a token
  /// @param _token The token to get the value parameters for
  /// @return params The value parameters for the token
  function getDefaultValueParams(IERC20 _token, ICLMMAdapter _adapter)
    external
    view
    returns (ValueParams memory params);

  /// @notice Gets the adapter for a token
  /// @param _token The token to get the adapter for
  /// @return adapter The adapter for the token
  function getTokenAdapter(IERC20 _token) external view returns (ICLMMAdapter);

  /// @notice Gets the fee for a token
  /// @param _token The token to get the fee for
  /// @return fee The fee for the token
  function getTokenFee(IERC20 _token) external view returns (uint24 fee);

  /// @notice Updates the referral settings
  /// @param _referralDestination The address to receive referrals
  /// @param _referralFee The new referral fee amount
  function setReferralSettings(address _referralDestination, uint256 _referralFee) external;

  /// @notice Updates the fee settings
  /// @param _feeDestination The address to receive fees
  /// @param _fee The new fee amount
  /// @param _feeDiscountAmount The amount of fee discount
  function setFeeSettings(address _feeDestination, uint256 _fee, uint256 _feeDiscountAmount) external;

  /// @notice Creates a new token launch
  /// @param p The parameters for the token launch
  /// @param expected The expected address where token will be deployed
  /// @param amount The amount of tokens to buy
  /// @param burnPosition Whether to burn the position
  /// @return token The address of the newly created token
  /// @return received The amount of tokens received if the user chooses to buy at launch
  /// @return swapped The amount of tokens swapped if the user chooses to swap at launch
  function createAndBuy(CreateParams memory p, address expected, uint256 amount, bool burnPosition)
    external
    payable
    returns (address token, uint256 received, uint256 swapped);

  /// @notice Gets the total number of tokens launched
  /// @return totalTokens The total count of launched tokens
  function getTotalTokens() external view returns (uint256 totalTokens);

  /// @notice Claims accumulated fees for a specific token
  /// @param _token The token to claim fees for
  function claimFees(IERC20 _token) external;

  /// @notice Toggle an adapter
  /// @param _adapter The adapter address
  function toggleAdapter(ICLMMAdapter _adapter) external;

  /// @notice Gets the launch parameters for a token
  /// @param _token The token to get the launch parameters for
  /// @return params The launch parameters for the token
  function getTokenLaunchParams(IERC20 _token) external view returns (CreateParams memory params);

  /// @notice Gets the claimed fees for a token
  /// @param _token The token to get the claimed fees for
  /// @return claimedFees0 The claimed fees for the token
  /// @return claimedFees1 The claimed fees for the token
  function claimedFees(IERC20 _token) external view returns (uint256 claimedFees0, uint256 claimedFees1);

  /// @notice Gets the claimed fees by creator for a token
  /// @param _creator The creator to get the claimed fees for
  /// @param _token The token to get the claimed fees for
  /// @return claimedFees0 The claimed fees for the token
  /// @return claimedFees1 The claimed fees for the token
  function claimedFeesByCreator(address _creator, IERC20 _token) external view returns (uint256 claimedFees0, uint256 claimedFees1);
}
