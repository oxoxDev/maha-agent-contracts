// SPDX-License-Identifier: BUSL-1.1

// ███╗   ███╗ █████╗ ██╗  ██╗ █████╗
// ████╗ ████║██╔══██╗██║  ██║██╔══██╗
// ██╔████╔██║███████║███████║███████║
// ██║╚██╔╝██║██╔══██║██╔══██║██╔══██║
// ██║ ╚═╝ ██║██║  ██║██║  ██║██║  ██║
// ╚═╝    ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝

// Website: https://wagmie.com
// Telegram: https://t.me/mahaxyz
// Twitter: https://twitter.com/mahaxyz_

pragma solidity ^0.8.0;

import {IERC20, TokenLaunchpad} from "contracts/launchpad/TokenLaunchpad.sol";

contract TokenLaunchpadBSC is TokenLaunchpad {
  function _distributeFees(address _token0, address _owner, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    if (_token1 == address(0x6A661312938D22A2A0e27F585073E4406903990a)) {
      // 100% to the owner if the fee is discounted
      IERC20(_token0).transfer(_owner, _amount0);
      IERC20(_token1).transfer(_owner, _amount1);
      creatorToClaimedFees[_owner][IERC20(_token0)][0] += _amount0;
      creatorToClaimedFees[_owner][IERC20(_token0)][1] += _amount1;
    } else {
      // 40% to MAHA treasury
      // 60% to the owner
      IERC20(_token0).transfer(feeDestination, _amount0 * 40 / 100);
      IERC20(_token1).transfer(feeDestination, _amount1 * 40 / 100);
      IERC20(_token0).transfer(_owner, _amount0 * 60 / 100);
      IERC20(_token1).transfer(_owner, _amount1 * 60 / 100);
      creatorToClaimedFees[_owner][IERC20(_token0)][0] += _amount0 * 60 / 100;
      creatorToClaimedFees[_owner][IERC20(_token0)][1] += _amount1 * 60 / 100;
    }
  }
}
