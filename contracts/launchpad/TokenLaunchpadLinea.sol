// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20, TokenLaunchpad} from "contracts/launchpad/TokenLaunchpad.sol";

contract TokenLaunchpadLinea is TokenLaunchpad {
  function _distributeFees(address _token0, address, address _token1, uint256 _amount0, uint256 _amount1)
    internal
    override
  {
    address nileTreasury = 0xF0FfFD0292dE675e865A9b506bd2c434e0813d74;
    address somethingTreasury = 0x5135f3A6aC33C8616b5ee59b89afc1021D1a8086;
    address efrogsTreasury = 0x4c11F940E2D09eF9D5000668c1C9410f0AaF0833;

    // 20% to the nile treasury
    // 40% to the maha treasury
    // 40% to the efrogs treasury

    IERC20(_token0).transfer(nileTreasury, _amount0 * 20 / 100);
    IERC20(_token0).transfer(somethingTreasury, _amount0 * 40 / 100);
    IERC20(_token0).transfer(efrogsTreasury, _amount0 * 40 / 100);

    IERC20(_token1).transfer(nileTreasury, _amount1 * 20 / 100);
    IERC20(_token1).transfer(somethingTreasury, _amount1 * 40 / 100);
    IERC20(_token1).transfer(efrogsTreasury, _amount1 * 40 / 100);
  }
}
