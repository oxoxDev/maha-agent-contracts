// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import {AgentToken} from "../contracts/token/AgentToken.sol";
import {RamsesAdapter} from "contracts/launchpad/clmm/dexes/RamsesAdapter.sol";

import {IAgentLaunchpad, IERC20} from "contracts/interfaces/IAgentLaunchpad.sol";
import {AgentLaunchpad} from "contracts/launchpad/clmm/AgentLaunchpad.sol";
import {MockERC20} from "contracts/mocks/MockERC20.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract AgentLaunchpadForkLineaTest is Test {
  AgentLaunchpad launchpad;
  MockERC20 weth;
  RamsesAdapter adapter;
  AgentToken tokenImpl;
  string LINEA_RPC_URL = vm.envString("LINEA_RPC_URL");

  address owner = makeAddr("owner");

  function setUp() public {
    uint256 lineaFork = vm.createFork(LINEA_RPC_URL);
    vm.selectFork(lineaFork);

    //     constructor(address _launchpad, address _clPoolFactory) {
    //   LAUNCHPAD = _launchpad;
    //   CL_POOL_FACTORY = IClPoolFactory(_clPoolFactory);
    //   me = address(this);
    // }

    launchpad = new AgentLaunchpad();
    adapter = new RamsesAdapter();
    weth = new MockERC20("Wrapped Ether", "WETH", 18);
    tokenImpl = new AgentToken();

    adapter.initialize(address(launchpad), address(0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42));
    launchpad.initialize(address(weth), address(adapter), address(tokenImpl), owner);
  }

  function test_create() public {
    IAgentLaunchpad.CreateParams memory params = IAgentLaunchpad.CreateParams({
      base: IAgentLaunchpad.CreateParamsBase({
        name: "Test Token",
        symbol: "TEST",
        metadata: "Test metadata",
        fundingToken: IERC20(address(weth)),
        fee: 3000,
        limitPerWallet: 1000,
        salt: bytes32(0)
      }),
      liquidity: IAgentLaunchpad.CreateParamsLiquidity({
        amountBaseBeforeTick: 600_000_000 ether,
        amountBaseAfterTick: 400_000_000 ether,
        initialSqrtPrice: 79_228_162_514_264_337_593_543_950_336, // sqrt(1) * 2^96 for 1 ETH per token
        lowerTick: 6931, // Price of 1 ETH per token
        upperTick: 6932, // Price of 2 ETH per token
        upperMaxTick: 46_052 // Price of 100 ETH per token
      })
    });

    launchpad.create(params);
  }
}
