// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SOMETHING
/// @notice A contract for funding Token
contract SOMETHING is ERC20{
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    _mint(msg.sender, 1_000_000_000 * 1e18); // 1 bn supply
  }
}
