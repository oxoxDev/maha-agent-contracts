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

  string LINEA_RPC_URL = vm.envString("LINEA_RPC_URL");

  function setUp() public {
    uint256 lineaFork = vm.createFork(LINEA_RPC_URL);
    vm.selectFork(lineaFork);
    _weth = IERC20(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);// WETH address on Linea

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

  function test_createAndBuy() public {
    ITokenLaunchpad.CreateParams memory params = _createParams();
    vm.prank(creator);
    (address tokenAddr,,) = _launchpad.createAndBuy{value: 100 ether}(params, address(0), 0, false);
    assertTrue(tokenAddr != address(0), "Token address should not be zero");
  }

  function _createParams() internal view returns (ITokenLaunchpad.CreateParams memory) {
    return ITokenLaunchpad.CreateParams({
      name: "Test Token",
      symbol: "TEST",
      metadata: "Test metadata",
      fundingToken: IERC20(address(_weth)),
      salt: findValidTokenHash("Test Token", "TEST", creator, _weth),
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
  }
}
