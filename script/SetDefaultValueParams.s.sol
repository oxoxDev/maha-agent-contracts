// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {ITokenLaunchpad} from "../contracts/interfaces/ITokenLaunchpad.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLMMAdapter} from "../contracts/interfaces/ICLMMAdapter.sol";
import {console} from "forge-std/console.sol";

contract SetDefaultValueParamsScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address launchpadAddress = 0xF0FfCbd64B3D3c85900BcfD1C39e31E41A20b66E;
        ITokenLaunchpad launchpad = ITokenLaunchpad(launchpadAddress);
        
        // Set the default value parameters
        launchpad.setDefaultValueParams(
            IERC20(0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f), // _token
            ICLMMAdapter(0x88C1C8ED7bbaf0A2c059F3b308A58AfA551bE351), // _adapter
            ITokenLaunchpad.ValueParams({
                fee: 3000,
                graduationLiquidity: 800000000000000000000000000,
                graduationTick: -160500,
                launchTick: -186600,
                tickSpacing: 60,
                upperMaxTick: 885000
            })
        );
        
        // Stop broadcasting transactions
        vm.stopBroadcast();
        
        console.log("Default value parameters set successfully!");
    }
}
