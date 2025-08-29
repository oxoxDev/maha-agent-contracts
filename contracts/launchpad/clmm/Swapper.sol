// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {ICLMMAdapter} from "contracts/interfaces/ICLMMAdapter.sol";
import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
contract Swapper {
  using SafeERC20 for IERC20;

  IWETH9 public immutable weth;
  address public immutable ODOS;
  ITokenLaunchpad public immutable launchpad;

  receive() external payable {}

  constructor(address _weth, address _odos, address _launchpad) {
    weth = IWETH9(_weth);
    ODOS = _odos;
    launchpad = ITokenLaunchpad(_launchpad);
  }

  /// @notice Buys a token with exact input using ODOS
  /// @param _odosTokenIn The ODOS token to receive
  /// @param _tokenIn The token to buy
  /// @param _tokenOut The token to receive
  /// @param _odosTokenInAmount The amount of ODOS tokens to receive
  /// @param _minOdosTokenOut The minimum amount of ODOS tokens to receive
  /// @param _minAmountOut The minimum amount of tokens to receive
  /// @param _odosData The data to pass to the ODOS contract
  function buyWithExactInputWithOdos(
    IERC20 _odosTokenIn,
    IERC20 _tokenIn,
    IERC20 _tokenOut,
    uint256 _odosTokenInAmount,
    uint256 _minOdosTokenOut,
    uint256 _minAmountOut,
    bytes memory _odosData
  ) public payable returns (uint256 amountOut) {
    if (msg.value > 0) weth.deposit{value: msg.value}();
    else _odosTokenIn.safeTransferFrom(msg.sender, address(this), _odosTokenInAmount);

    uint24 fee = launchpad.getTokenFee(_tokenOut);
    ICLMMAdapter adapter = launchpad.getTokenAdapter(_tokenOut);

    // call the odos contract to get the amount of tokens to buy
    if (_odosData.length > 10) {
      _odosTokenIn.approve(address(ODOS), type(uint256).max);
      (bool success,) = ODOS.call(_odosData);
      require(success, "!odos");
    } else {
      require(_odosTokenIn == _tokenIn, "!odosTokenIn");
    }

    // ensure that the odos has given us enough tokens to perform the raw swap
    uint256 amountIn = _tokenIn.balanceOf(address(this));
    require(amountIn >= _minOdosTokenOut, "!minAmountIn");

    _tokenIn.approve(address(adapter), type(uint256).max);
    amountOut = adapter.swapWithExactInput(_tokenIn, _tokenOut, amountIn, _minAmountOut, fee);

    // send everything back
    _refundTokens(_tokenIn);
    _refundTokens(_tokenOut);
    _refundTokens(_odosTokenIn);

    // collect fees
    launchpad.claimFees(_tokenOut);
  }

  /// @notice Sells a token with exact input using ODOS
  /// @param _tokenIn The token to sell
  /// @param _odosTokenOut The ODOS token to receive
  /// @param _tokenOut The token to receive
  /// @param _tokenInAmount The amount of tokens to sell
  /// @param _minOdosTokenIn The minimum amount of ODOS tokens to receive
  /// @param _minAmountOut The minimum amount of tokens to receive
  /// @param _odosData The data to pass to the ODOS contract
  function sellWithExactInputWithOdos(
    IERC20 _tokenIn,
    IERC20 _odosTokenOut,
    IERC20 _tokenOut,
    uint256 _tokenInAmount,
    uint256 _minOdosTokenIn,
    uint256 _minAmountOut,
    bytes memory _odosData
  ) public payable returns (uint256 amountOut) {
    ICLMMAdapter adapter = launchpad.getTokenAdapter(_tokenIn);
    uint24 fee = launchpad.getTokenFee(_tokenIn);

    _tokenIn.safeTransferFrom(msg.sender, address(this), _tokenInAmount);
    _tokenIn.approve(address(adapter), type(uint256).max);

    uint256 amountSwapOut = adapter.swapWithExactInput(_tokenIn, _odosTokenOut, _tokenInAmount, _minOdosTokenIn, fee);

    if (_odosData.length > 10) {
      _odosTokenOut.approve(ODOS, type(uint256).max);
      (bool success,) = ODOS.call(_odosData);
      require(success, "!odos");
      amountOut = _tokenOut.balanceOf(address(this));
    } else {
      require(_odosTokenOut == _tokenOut, "!odosTokenOut");
      amountOut = amountSwapOut;
    }

    require(amountOut >= _minAmountOut, "!minAmountOut");

    // send everything back
    _refundTokens(_tokenIn);
    _refundTokens(_tokenOut);
    _refundTokens(_odosTokenOut);

    // collect fees
    launchpad.claimFees(_tokenIn);
  }

  /// @dev Refund tokens to the owner
  /// @param _token The token to refund
  function _refundTokens(IERC20 _token) internal {
    uint256 remaining = _token.balanceOf(address(this));
    if (remaining == 0) return;
    if (_token == weth) {
      weth.withdraw(remaining);
      payable(msg.sender).transfer(remaining);
    } else {
      _token.safeTransfer(msg.sender, remaining);
    }
  }
}
