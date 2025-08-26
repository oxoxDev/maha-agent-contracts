// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {IFreeUniV3LPLocker, MockERC20, TokenLaunchpadTest} from "./TokenLaunchpadTest.sol";

import {Launchpool} from "contracts/Launchpool.sol";
import { AirdropRewarder } from "contracts/airdrop/AirdropReward.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20, ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {ILaunchpool} from "contracts/interfaces/ILaunchpool.sol";
import {TokenLaunchpadBSC} from "contracts/launchpad/TokenLaunchpadBSC.sol";
import {Swapper} from "contracts/launchpad/clmm/Swapper.sol";
import {PancakeAdapter} from "contracts/launchpad/clmm/adapters/PancakeAdapter.sol";
import {ThenaAdapter} from "contracts/launchpad/clmm/adapters/ThenaAdapter.sol";
import {ThenaLocker} from "contracts/launchpad/clmm/locker/ThenaLocker.sol";

contract TokenLaunchpadBscForkTest is TokenLaunchpadTest {
  // BSC Mainnet addresses
  address constant PANCAKE_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
  address constant PANCAKE_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
  address constant NFT_MANAGER = 0x46A15B0b27311cedF172AB29E4f4766fbE7F4364;
  address constant LOCKER = 0x25c9C4B56E820e0DEA438b145284F02D9Ca9Bd52;

  address constant THE_NFT_POSITION_MANAGER = 0xa51ADb08Cbe6Ae398046A23bec013979816B77Ab;
  address constant THE_CL_POOL_FACTORY = 0x306F06C147f064A010530292A1EB6737c3e378e4;
  address constant THE_SWAP_ROUTER = 0x327Dd3208f0bCF590A66110aCB6e5e6941A4EfA0;

  PancakeAdapter _adapterPCS;
  ThenaAdapter _adapterThena;
  ThenaLocker _lockerThena;
  Swapper _swapper;
  AirdropRewarder _airdropRewarder;

  string BSC_RPC_URL = vm.envString("BSC_RPC_URL");

  function setUp() public {
    uint256 bscFork = vm.createFork(BSC_RPC_URL);
    vm.selectFork(bscFork);
    _weth = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);// WBNB address on BSC

    _setUpBase();

    // Initialize locker
    _lockerThena = new ThenaLocker(THE_NFT_POSITION_MANAGER);

    _launchpad = new TokenLaunchpadBSC();
    _adapterPCS =
      new PancakeAdapter(address(_launchpad), PANCAKE_FACTORY, PANCAKE_ROUTER, address(_weth), LOCKER, NFT_MANAGER);
    _adapterThena = new ThenaAdapter(
      address(_launchpad),
      THE_CL_POOL_FACTORY,
      THE_SWAP_ROUTER,
      address(_weth),
      address(_lockerThena),
      THE_NFT_POSITION_MANAGER
    );

    _airdropRewarder = new AirdropRewarder();
    _airdropRewarder.initialize(address(_launchpad));

    // Label contracts for better trace output
    vm.label(address(_launchpad), "launchpad");
    vm.label(address(_adapterPCS), "adapterPCS");
    vm.label(address(_adapterThena), "adapterThena");
    vm.label(PANCAKE_FACTORY, "factoryPCS");
    vm.label(THE_CL_POOL_FACTORY, "factoryThena");
    vm.label(LOCKER, "locker");
    vm.label(NFT_MANAGER, "nftManager");
    vm.label(PANCAKE_ROUTER, "routerPCS");
    vm.label(THE_SWAP_ROUTER, "routerThena");

    // Initialize launchpad
    _swapper = new Swapper(address(_weth), address(0), address(_launchpad));

    // Initialize launchpad
    _launchpad.initialize(owner, address(_weth));
    vm.startPrank(owner);
    _launchpad.setFeeSettings(address(0x123), 0, 1000e18);
    _launchpad.toggleAdapter(_adapterPCS);
    _launchpad.toggleAdapter(_adapterThena);
    _launchpad.setDefaultValueParams(
      _weth,
      _adapterPCS,
      ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      })
    );
    _launchpad.setDefaultValueParams(
      _weth,
      _adapterThena,
      ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_760,
        upperMaxTick: 887_220,
        fee: 10_000,
        tickSpacing: 60,
        graduationLiquidity: 800_000_000 ether
      })
    );
    vm.stopPrank();
  }

  function test_create_pcs() public {
    bytes32 salt = findValidTokenHash("Test Token", "TEST", creator, _weth);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterPCS
    });

    vm.prank(creator);
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);

    assertTrue(tokenAddr != address(0), "Token address should not be zero");
  }

  function test_create_thena() public {
    bytes32 salt = findValidTokenHash("Test Token", "TEST2", creator, _weth);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST2",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterThena
    });

    vm.prank(creator);
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, 0x0aC8F0205dD95C0b0D044b1fC4cB5d90A47Cf614, 0, false);

    assertTrue(tokenAddr != address(0), "Token address should not be zero");
  }

  function test_swap_pcs() public {
    bytes32 salt = findValidTokenHash("Test Token", "TEST", creator, _weth);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterPCS
    });

    vm.prank(creator);
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);

    assertTrue(tokenAddr != address(0), "Token address should not be zero");

    vm.startPrank(creator);

    // Swap 10 WETH for the token
    _swapper.buyWithExactInputWithOdos{value: 10 ether}(
      IERC20(_weth), IERC20(_weth), IERC20(tokenAddr), 10 ether, 0, 0, "0x"
    );

    // // Swap 1 token for the weth
    IERC20(tokenAddr).approve(address(_swapper), 1 ether);
    _swapper.sellWithExactInputWithOdos(IERC20(tokenAddr), IERC20(_weth), IERC20(_weth), 1 ether, 0, 0, "0x");
    vm.stopPrank();

    // check for claimed fees
    (uint256 claimedFees0, uint256 claimedFees1) = _launchpad.claimedFees(IERC20(tokenAddr));
    assertNotEq(claimedFees0, 0, "Claimed fees should not be 0");
    assertNotEq(claimedFees1, 0, "Claimed fees should not be 0"); 

    // check for claimed fees by creator
    (claimedFees0, claimedFees1) = _launchpad.claimedFeesByCreator(creator, IERC20(tokenAddr));
    assertNotEq(claimedFees0, 0, "Claimed fees should not be 0");
    assertNotEq(claimedFees1, 0, "Claimed fees should not be 0");

    // claim fees
    _launchpad.claimFees(IERC20(tokenAddr));
  }

  function test_swap_thena() public {
    bytes32 salt = findValidTokenHash("Test Token", "TEST2", creator, _weth);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST2",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterThena
    });

    vm.prank(creator);
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);

    assertTrue(tokenAddr != address(0), "Token address should not be zero");

    vm.startPrank(creator);

    // Swap 10 WETH for the token
    _swapper.buyWithExactInputWithOdos{value: 10 ether}(
      IERC20(_weth), IERC20(_weth), IERC20(tokenAddr), 10 ether, 0, 0, "0x"
    );

    // Swap 1 token for the weth
    IERC20(tokenAddr).approve(address(_swapper), 1 ether);
    _swapper.sellWithExactInputWithOdos(IERC20(tokenAddr), IERC20(_weth), IERC20(_weth), 1 ether, 0, 0, "0x");
    vm.stopPrank();
  }

  function test_premium_token_uses_custom_params_pcs() public {
    // Mint MAHA tokens for creator to pay premium fee
    _maha.mint(owner, 10_000e18);

    // Deploy a real Launchpool contract for premium token
    Launchpool launchpool = new Launchpool();
    launchpool.initialize("Staking Pool", "STKP", address(_stakingToken), owner, address(_launchpad));

    // Capture initial historyIndex for launchpool verification
    uint32 initialHistoryIndex = launchpool.historyIndex();

    // Custom value parameters different from defaults
    ITokenLaunchpad.ValueParams memory customParams = ITokenLaunchpad.ValueParams({
      launchTick: -172_000,
      graduationTick: -171_800,
      upperMaxTick: 886_200,
      fee: 10_000,
      tickSpacing: 200,
      graduationLiquidity: 500_000_000 ether
    });

    bytes32 salt = findValidTokenHash("Test Token", "TEST", owner, _weth);

    // Track fee destination's initial MAHA balance
    uint256 initialMahaBalance = _maha.balanceOf(feeDestination);

    vm.prank(owner);
    _launchpad.setFeeSettings(feeDestination, 0, 1000e18);

    // Set up launchpool with allocations
    ILaunchpool[] memory launchpools = new ILaunchpool[](1);
    launchpools[0] = launchpool;

    uint256[] memory launchpoolAmounts = new uint256[](1);
    launchpoolAmounts[0] = 100_000 ether;

    vm.startPrank(owner);

    // Approve MAHA tokens for premium fee
    _maha.approve(address(_launchpad), 10_000e18);

    // Create token with premium flag and launchpool
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams,
      launchPoolAmounts: launchpoolAmounts,
      adapter: _adapterPCS
    });

    // Buy with 10 WETH
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);
    vm.stopPrank();

    // Verify premium fee was paid in MAHA
    assertEq(_maha.balanceOf(feeDestination), initialMahaBalance + 1000e18, "Premium fee not paid correctly in MAHA");

    // Get the actual parameters used from storage
    ITokenLaunchpad.CreateParams memory storedParams = _launchpad.getTokenLaunchParams(IERC20(tokenAddr));
    // Custom params should be used for premium tokens
    assertEq(storedParams.valueParams.launchTick, customParams.launchTick, "Custom launchTick not used");
    assertEq(storedParams.valueParams.graduationTick, customParams.graduationTick, "Custom graduationTick not used");
    assertEq(storedParams.valueParams.upperMaxTick, customParams.upperMaxTick, "Custom upperMaxTick not used");
    assertEq(storedParams.valueParams.fee, customParams.fee, "Custom fee not used");
    assertEq(storedParams.valueParams.tickSpacing, customParams.tickSpacing, "Custom tickSpacing not used");
    assertEq(
      storedParams.valueParams.graduationLiquidity,
      customParams.graduationLiquidity,
      "Custom graduationLiquidity not used"
    );

    // keep this on hold for now
    // // LAUNCHPOOL VERIFICATION - Premium tokens can use launchpools
    // // 1. Verify RewardDrop was created in the launchpool
    // (IERC20 rewardToken, uint256 totalReward, uint32 snapshotIndex) = launchpool.rewardDrops(IERC20(tokenAddr));

    // // 2. Verify correct reward token was set
    // assertEq(address(rewardToken), tokenAddr, "Incorrect reward token in launchpool");

    // // 3. Verify reward amount
    // assertEq(totalReward, 100_000 ether, "Incorrect reward amount in launchpool");

    // // 4. Verify snapshotIndex was captured
    // assertEq(snapshotIndex, initialHistoryIndex, "Incorrect snapshot index in launchpool");

    // // 5. Verify that launch parameters include this launchpool
    // assertEq(address(storedParams.launchPools[0]), address(launchpool), "Launchpool not stored correctly");
    // assertEq(storedParams.launchPoolAmounts[0], 100_000 ether, "Launchpool amount not stored correctly");
  }

  function test_premium_token_uses_custom_params_thena() public {
    // Mint MAHA tokens for creator to pay premium fee
    _maha.mint(owner, 10_000e18);

    // Deploy a real Launchpool contract for premium token
    Launchpool launchpool = new Launchpool();
    launchpool.initialize("Staking Pool", "STKP", address(_stakingToken), owner, address(_launchpad));

    // Capture initial historyIndex for launchpool verification
    uint32 initialHistoryIndex = launchpool.historyIndex();

    // Custom value parameters - significantly different from defaults
    ITokenLaunchpad.ValueParams memory customParams = ITokenLaunchpad.ValueParams({
      launchTick: -171_000,
      graduationTick: -170_760,
      upperMaxTick: 887_220,
      fee: 500,
      tickSpacing: 60,
      graduationLiquidity: 500_000_000 ether
    });

    bytes32 salt = findValidTokenHash("Test Token", "TEST", owner, _weth);

    // Track fee destination's initial MAHA balance
    uint256 initialMahaBalance = _maha.balanceOf(feeDestination);

    // Set up launchpool with allocations
    ILaunchpool[] memory launchpools = new ILaunchpool[](1);
    launchpools[0] = launchpool;

    uint256[] memory launchpoolAmounts = new uint256[](1);
    launchpoolAmounts[0] = 100_000 ether;

    vm.startPrank(owner);

    // Approve MAHA tokens for premium fee
    _maha.approve(address(_launchpad), 10_000e18);

    _launchpad.setFeeSettings(feeDestination, 0, 1000e18);

    // Create token with premium flag and launchpool
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams,
      launchPoolAmounts: launchpoolAmounts,
      adapter: _adapterThena
    });

    // Buy with 10 WETH
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);
    vm.stopPrank();

    // Verify premium fee was paid in MAHA
    assertEq(_maha.balanceOf(feeDestination), initialMahaBalance + 1000e18, "Premium fee not paid correctly in MAHA");

    // Get the actual parameters used from storage
    ITokenLaunchpad.CreateParams memory storedParams = _launchpad.getTokenLaunchParams(IERC20(tokenAddr));
    // Custom params should be used for premium tokens
    assertEq(storedParams.valueParams.launchTick, customParams.launchTick, "Custom launchTick not used");
    assertEq(storedParams.valueParams.graduationTick, customParams.graduationTick, "Custom graduationTick not used");
    assertEq(storedParams.valueParams.upperMaxTick, customParams.upperMaxTick, "Custom upperMaxTick not used");
    assertEq(storedParams.valueParams.fee, customParams.fee, "Custom fee not used");
    assertEq(storedParams.valueParams.tickSpacing, customParams.tickSpacing, "Custom tickSpacing not used");
    assertEq(
      storedParams.valueParams.graduationLiquidity,
      customParams.graduationLiquidity,
      "Custom graduationLiquidity not used"
    );

    // keep this on hold for now
    // // LAUNCHPOOL VERIFICATION - Premium tokens can use launchpools
    // // 1. Verify RewardDrop was created in the launchpool
    // (IERC20 rewardToken, uint256 totalReward, uint32 snapshotIndex) = launchpool.rewardDrops(IERC20(tokenAddr));

    // // 2. Verify correct reward token was set
    // assertEq(address(rewardToken), tokenAddr, "Incorrect reward token in launchpool");

    // // 3. Verify reward amount
    // assertEq(totalReward, 100_000 ether, "Incorrect reward amount in launchpool");

    // // 4. Verify snapshotIndex was captured
    // assertEq(snapshotIndex, initialHistoryIndex, "Incorrect snapshot index in launchpool");

    // // 5. Verify that launch parameters include this launchpool
    // assertEq(address(storedParams.launchPools[0]), address(launchpool), "Launchpool not stored correctly");
    // assertEq(storedParams.launchPoolAmounts[0], 100_000 ether, "Launchpool amount not stored correctly");
  }

  function test_non_premium_token_uses_default_params_pcs() public {
    // Create a Launchpool instance - will be used to verify non-premium tokens can't use it
    Launchpool launchpool = new Launchpool();
    launchpool.initialize("Staking Pool", "STKP", address(_stakingToken), owner, address(_launchpad));

    // Custom parameters that will be ignored
    ITokenLaunchpad.ValueParams memory customParams = ITokenLaunchpad.ValueParams({
      launchTick: -172_000,
      graduationTick: -171_800,
      upperMaxTick: 886_200,
      fee: 10_000,
      tickSpacing: 200,
      graduationLiquidity: 800_000_000 ether
    });

    bytes32 salt = findValidTokenHash("Non-Premium Token", "NORM", owner, _weth);

    vm.startPrank(owner);

    // First confirm that attempting to use launchpools with non-premium token will revert
    ILaunchpool[] memory launchpools = new ILaunchpool[](1);
    launchpools[0] = launchpool;

    uint256[] memory launchpoolAmounts = new uint256[](1);
    launchpoolAmounts[0] = 1_000_000 ether;

    ITokenLaunchpad.CreateParams memory paramsWithLaunchpool = ITokenLaunchpad.CreateParams({
      name: "Non-Premium Token",
      symbol: "NORM",
      metadata: "Non-premium token with launchpool - should fail",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams,
      launchPoolAmounts: launchpoolAmounts,
      adapter: _adapterPCS
    });

    _launchpad.setDefaultValueParams(_weth, _adapterPCS, customParams);

    // Verify that non-premium tokens cannot have launchpools
    vm.expectRevert("!premium-allocations");
    _launchpad.createAndBuy{value: 100 ether}(paramsWithLaunchpool, address(0), 10 ether, false);

    // Now create a valid non-premium token with no launchpools
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Non-Premium Token",
      symbol: "NORM",
      metadata: "Non-premium token uses default params",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams, // These should be ignored/overridden
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterPCS
    });

    // Create token
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 10 ether, false);
    vm.stopPrank();

    // Get the actual parameters used from storage
    ITokenLaunchpad.CreateParams memory storedParams = _launchpad.getTokenLaunchParams(IERC20(tokenAddr));
    ITokenLaunchpad.ValueParams memory defaultValueParams = _launchpad.getDefaultValueParams(_weth, _adapterPCS);

    // Default params should be used for non-premium tokens
    assertEq(storedParams.valueParams.launchTick, defaultValueParams.launchTick, "Default launchTick not used");
    assertEq(
      storedParams.valueParams.graduationTick, defaultValueParams.graduationTick, "Default graduationTick not used"
    );
    assertEq(storedParams.valueParams.upperMaxTick, defaultValueParams.upperMaxTick, "Default upperMaxTick not used");
    assertEq(storedParams.valueParams.fee, defaultValueParams.fee, "Default fee not used");
    assertEq(storedParams.valueParams.tickSpacing, defaultValueParams.tickSpacing, "Default tickSpacing not used");
    assertEq(
      storedParams.valueParams.graduationLiquidity,
      defaultValueParams.graduationLiquidity,
      "Default graduationLiquidity not used"
    );
  }

  function test_non_premium_token_uses_default_params_thena() public {
    // Create a Launchpool instance - will be used to verify non-premium tokens can't use it
    Launchpool launchpool = new Launchpool();
    launchpool.initialize("Staking Pool", "STKP", address(_stakingToken), owner, address(_launchpad));

    // Custom parameters that will be ignored
    ITokenLaunchpad.ValueParams memory customParams = ITokenLaunchpad.ValueParams({
      launchTick: -172_000,
      graduationTick: -171_800,
      upperMaxTick: 886_200,
      fee: 500,
      tickSpacing: 10_000,
      graduationLiquidity: 500_000_000 ether
    });

    bytes32 salt = findValidTokenHash("Non-Premium Token", "NORM", owner, _weth);

    vm.startPrank(owner);

    // First confirm that attempting to use launchpools with non-premium token will revert
    ILaunchpool[] memory launchpools = new ILaunchpool[](1);
    launchpools[0] = launchpool;

    uint256[] memory launchpoolAmounts = new uint256[](1);
    launchpoolAmounts[0] = 1_000_000 ether;

    ITokenLaunchpad.CreateParams memory paramsWithLaunchpool = ITokenLaunchpad.CreateParams({
      name: "Non-Premium Token",
      symbol: "NORM",
      metadata: "Non-premium token with launchpool - should fail",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams,
      launchPoolAmounts: launchpoolAmounts,
      adapter: _adapterThena
    });

    // Verify that non-premium tokens cannot have launchpools
    vm.expectRevert("!premium-allocations");
    _launchpad.createAndBuy{value: 100 ether}(paramsWithLaunchpool, address(0), 10 ether, false);

    // Now create a valid non-premium token with no launchpools
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Non-Premium Token",
      symbol: "NORM",
      metadata: "Non-premium token uses default params",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: customParams, // These should be ignored/overridden
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterThena
    });

    // Create token
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 10 ether, false);
    vm.stopPrank();

    // Get the actual parameters used from storage
    ITokenLaunchpad.CreateParams memory storedParams = _launchpad.getTokenLaunchParams(IERC20(tokenAddr));
    ITokenLaunchpad.ValueParams memory defaultValueParams = _launchpad.getDefaultValueParams(_weth, _adapterThena);

    // Default params should be used for non-premium tokens
    assertEq(storedParams.valueParams.launchTick, defaultValueParams.launchTick, "Default launchTick not used");
    assertEq(
      storedParams.valueParams.graduationTick, defaultValueParams.graduationTick, "Default graduationTick not used"
    );
    assertEq(storedParams.valueParams.upperMaxTick, defaultValueParams.upperMaxTick, "Default upperMaxTick not used");
    assertEq(storedParams.valueParams.fee, defaultValueParams.fee, "Default fee not used");
    assertEq(storedParams.valueParams.tickSpacing, defaultValueParams.tickSpacing, "Default tickSpacing not used");
    assertEq(
      storedParams.valueParams.graduationLiquidity,
      defaultValueParams.graduationLiquidity,
      "Default graduationLiquidity not used"
    );
  }

  function test_create_not_eth_pcs() public {
    MockERC20 _token = new MockERC20("Best Token", "BEST", 18);
    _token.mint(creator, 1_000_000_000 ether);
    vm.label(address(_token), "bestToken");

    //set Default Value Params
    vm.prank(owner);
    _launchpad.setDefaultValueParams(
      _token,
      _adapterPCS,
      ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      })
    );

    bytes32 salt = findValidTokenHash("Test Token", "TEST", creator, _token);

    vm.startPrank(creator);
    _token.approve(address(_launchpad), 1_000_000_000 ether);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_token)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_000,
        upperMaxTick: 887_000,
        fee: 1000,
        tickSpacing: 20_000,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterPCS
    });
    _launchpad.createAndBuy{value: 0.1 ether}(params, address(0), 10 ether, false);
  }

  function test_create_not_eth_thena() public {
    MockERC20 _token = new MockERC20("Best Token", "BEST", 18);
    _token.mint(creator, 1_000_000_000 ether);
    vm.label(address(_token), "bestToken");

    //set Default Value Params
    vm.prank(owner);
    _launchpad.setDefaultValueParams(
      _token,
      _adapterThena,
      ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_760,
        upperMaxTick: 887_220,
        fee: 10_000,
        tickSpacing: 60,
        graduationLiquidity: 800_000_000 ether
      })
    );

    bytes32 salt = findValidTokenHash("Test Token", "TEST", creator, _token);

    vm.startPrank(creator);
    _token.approve(address(_launchpad), 1_000_000_000 ether);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_token)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_000,
        upperMaxTick: 887_000,
        fee: 1000,
        tickSpacing: 20_000,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterThena
    });
    _launchpad.createAndBuy{value: 0.1 ether}(params, address(0), 10 ether, false);
  }

  function test_mintAndBurn_pcs() public {
    address deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint256 balanceBefore = IERC721(NFT_MANAGER).balanceOf(deadAddress);
    bytes32 salt = findValidTokenHash("Test Token", "TEST", creator, _weth);
    ITokenLaunchpad.CreateParams memory params = ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: salt,
      valueParams: ITokenLaunchpad.ValueParams({
        launchTick: -171_000,
        graduationTick: -170_800,
        upperMaxTick: 887_200,
        fee: 10_000,
        tickSpacing: 200,
        graduationLiquidity: 800_000_000 ether
      }),
      launchPoolAmounts: new uint256[](0),
      adapter: _adapterPCS
    });

    vm.prank(creator);
    _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);

    uint256 balanceAfter = IERC721(NFT_MANAGER).balanceOf(deadAddress);
    assertEq(balanceAfter, balanceBefore + 2, "NFT should be transferred to dead address");
  }
}
