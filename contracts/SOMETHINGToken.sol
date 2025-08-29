// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title SOMETHINGToken
/// @notice A contract for creating and managing tokens with presale functionality
contract SOMETHINGToken is ERC20, Ownable {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {
    _mint(msg.sender, 1_000_000_000 * 1e18); // 1 bn supply
    _transferOwnership(address(0));
  }
}
