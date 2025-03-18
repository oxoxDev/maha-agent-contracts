// SPDX-License-Identifier: BUSL-1.1

// ███╗   ███╗ █████╗ ██╗  ██╗ █████╗
// ████╗ ████║██╔══██╗██║  ██║██╔══██╗
// ██╔████╔██║███████║███████║███████║
// ██║╚██╔╝██║██╔══██║██╔══██║██╔══██║
// ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██║
// ╚═╝    ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝

// Website: https://maha.xyz
// Discord: https://discord.gg/mahadao
// Twitter: https://twitter.com/mahaxyz_

pragma solidity ^0.8.0;

import {AgentLaunchpadBase} from "./AgentLaunchpadBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPool} from "contracts/aerodrome/interfaces/IPool.sol";

import {IAgentToken} from "contracts/interfaces/IAgentToken.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";

abstract contract AgentLaunchpadLocker is AgentLaunchpadBase {
  function _lockLiquidity(IAgentToken token, address pool) internal {
    require(liquidityLocks[address(token)].amount == 0, "lock exists");
    liquidityLocks[address(token)] =
      LiquidityLock({liquidityToken: IPool(pool), amount: IERC20(pool).balanceOf(address(this))});
    emit LiquidityLocked(address(token), pool, IERC20(pool).balanceOf(address(this)));
  }

  function claimFees(IERC20 token) external {
    // LiquidityLock storage lock = liquidityLocks[token];
    // require(lock.amount != 0, "No lock locked");

    // address dest = ownerOf(tokenToNftId[IAgentToken(token)]);

    // (uint256 fee0, uint256 fee1) = adapter.claimFees(token);

    // uint256 bribeAmount = (fee0 + fee1) * 20 / 100; // 20% to nile as bribes
    // uint256 launchpadAmount = (fee0 + fee1) * 40 / 100; // 40% to the launchpad
    // uint256 creatorAmount = (fee0 + fee1) * 40 / 100; // 40% to the creator

    // IERC20(token.token0()).transfer(dest, fee0);
    // IERC20(token.token1()).transfer(dest, fee1);
    // IPool pool = lock.liquidityToken;
    // (uint256 fee0, uint256 fee1) = adapter.claimFees(token);

    // IERC20(pool.token0()).transfer(dest, fee0);
    // IERC20(pool.token1()).transfer(dest, fee1);
  }
}
