// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IWETH9} from "@uniswap/v4-periphery/src/interfaces/external/IWETH9.sol";
import {ICLMMAdapter, IClPool} from "contracts/interfaces/ICLMMAdapter.sol";

import {ITokenLaunchpad} from "contracts/interfaces/ITokenLaunchpad.sol";
import {ICLSwapRouter} from "contracts/interfaces/thirdparty/ICLSwapRouter.sol";
import {IClPoolFactory} from "contracts/interfaces/thirdparty/IClPoolFactory.sol";

abstract contract BaseV3Adapter is ICLMMAdapter {
  using SafeERC20 for IERC20;

  address internal _me;
  address public launchpad;
  IClPoolFactory public clPoolFactory;
  ICLSwapRouter public swapRouter;
  address public locker;
  IERC721 public nftPositionManager;
  IWETH9 public WETH9;

  mapping(IERC20 token => mapping(uint256 index => uint256 lockId)) public tokenToLockId;
  mapping(IERC20 token => mapping(uint256 index => uint256 claimedFees)) public tokenToClaimedFees;

  function __BaseV3Adapter_init(
    address _launchpad,
    address _WETH9,
    address _locker,
    address _swapRouter,
    address _nftPositionManager,
    address _clPoolFactory
  ) internal {
    _me = address(this);

    clPoolFactory = IClPoolFactory(_clPoolFactory);
    launchpad = _launchpad;
    locker = _locker;
    nftPositionManager = IERC721(_nftPositionManager);
    swapRouter = ICLSwapRouter(_swapRouter);
    WETH9 = IWETH9(_WETH9);

    nftPositionManager.setApprovalForAll(address(locker), true);
  }

  /// @inheritdoc ICLMMAdapter
  function swapWithExactOutput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountOut, uint256 _maxAmountIn, uint24 _fee)
    external
    virtual
    returns (uint256 amountIn)
  {
    _tokenIn.safeTransferFrom(msg.sender, address(this), _maxAmountIn);
    _tokenIn.approve(address(swapRouter), type(uint256).max);
    amountIn = swapRouter.exactOutputSingle(
      ICLSwapRouter.ExactOutputSingleParams({
        tokenIn: address(_tokenIn),
        tokenOut: address(_tokenOut),
        amountOut: _amountOut,
        recipient: msg.sender,
        deadline: block.timestamp,
        fee: _fee,
        amountInMaximum: _maxAmountIn,
        sqrtPriceLimitX96: 0
      })
    );
    _refundTokens(_tokenIn);
  }

  /// @inheritdoc ICLMMAdapter
  function swapWithExactInput(IERC20 _tokenIn, IERC20 _tokenOut, uint256 _amountIn, uint256 _minAmountOut, uint24 _fee)
    external
    virtual
    returns (uint256 amountOut)
  {
    _tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);
    _tokenIn.approve(address(swapRouter), type(uint256).max);

    amountOut = swapRouter.exactInputSingle(
      ICLSwapRouter.ExactInputSingleParams({
        tokenIn: address(_tokenIn),
        tokenOut: address(_tokenOut),
        amountIn: _amountIn,
        recipient: msg.sender,
        deadline: block.timestamp,
        fee: _fee,
        amountOutMinimum: _minAmountOut,
        sqrtPriceLimitX96: 0
      })
    );
  }

  /// @inheritdoc ICLMMAdapter
  function addSingleSidedLiquidity(AddLiquidityParams memory _params) external returns (address) {
    require(msg.sender == launchpad, "!launchpad");

    uint160 sqrtPriceX96Launch = TickMath.getSqrtPriceAtTick(_params.tick0 - 1);

    IClPool pool = _createPool(_params.tokenBase, _params.tokenQuote, _params.fee, sqrtPriceX96Launch);

    if (!_params.burnPosition) {
      // calculate and add liquidity for the various tick ranges
      _mintAndLock(
        _params.tokenBase, _params.tokenQuote, _params.tick0, _params.tick1, _params.fee, _params.graduationAmount, 0
      );

      _mintAndLock(
        _params.tokenBase,
        _params.tokenQuote,
        _params.tick1,
        _params.tick2,
        _params.fee,
        _params.totalAmount - _params.graduationAmount,
        1
      );
    } else {
      _mintAndBurn(
        _params.tokenBase, _params.tokenQuote, _params.tick0, _params.tick1, _params.fee, _params.graduationAmount
      );
      _mintAndBurn(
        _params.tokenBase,
        _params.tokenQuote,
        _params.tick1,
        _params.tick2,
        _params.fee,
        _params.totalAmount - _params.graduationAmount
      );
    }

    return address(pool);
  }

  /// @inheritdoc ICLMMAdapter
  function claimFees(address _token) external returns (uint256 fee0, uint256 fee1) {
    require(msg.sender == launchpad, "!launchpad");

    uint256 lockId0 = tokenToLockId[IERC20(_token)][0];
    uint256 lockId1 = tokenToLockId[IERC20(_token)][1];

    (uint256 fee00, uint256 fee01) = _collectFees(lockId0);
    (uint256 fee10, uint256 fee11) = _collectFees(lockId1);

    fee0 = fee00 + fee10;
    fee1 = fee01 + fee11;

    tokenToClaimedFees[IERC20(_token)][0] += fee0;
    tokenToClaimedFees[IERC20(_token)][1] += fee1;

    IERC20 quoteToken = ITokenLaunchpad(launchpad).getQuoteToken(IERC20(_token));
    IERC20(_token).transfer(msg.sender, fee0);
    quoteToken.transfer(msg.sender, fee1);
  }

  function claimedFees(address _token) external view returns (uint256 fee0, uint256 fee1) {
    fee0 = tokenToClaimedFees[IERC20(_token)][0];
    fee1 = tokenToClaimedFees[IERC20(_token)][1];
  }

  /// @dev Refund tokens to the owner
  /// @param _token The token to refund
  function _refundTokens(IERC20 _token) internal {
    uint256 remaining = _token.balanceOf(address(this));
    if (remaining == 0) return;
    _token.safeTransfer(msg.sender, remaining);
  }

  /// @dev Mint a position and lock it forever
  /// @param _token0 The token to mint the position for
  /// @param _token1 The token to mint the position for
  /// @param _tick0 The lower tick of the position
  /// @param _tick1 The upper tick of the position
  /// @param _fee The fee of the pool
  /// @param _amount0 The amount of tokens to mint the position for
  /// @param _index The index of the position
  /// @return lockId The lock id of the position
  function _mintAndLock(
    IERC20 _token0,
    IERC20 _token1,
    int24 _tick0,
    int24 _tick1,
    uint24 _fee,
    uint256 _amount0,
    uint256 _index
  ) internal virtual returns (uint256 lockId);

  /// @dev Mint a position and lock it forever
  /// @param _token0 The token to mint the position for
  /// @param _token1 The token to mint the position for
  /// @param _tick0 The lower tick of the position
  /// @param _tick1 The upper tick of the position
  /// @param _fee The fee of the pool
  /// @param _amount0 The amount of tokens to mint the position for
  function _mintAndBurn(IERC20 _token0, IERC20 _token1, int24 _tick0, int24 _tick1, uint24 _fee, uint256 _amount0)
    internal
    virtual;

  function _collectFees(uint256 _lockId) internal virtual returns (uint256 fee0, uint256 fee1);

  /// @dev Create a pool
  /// @param _token0 The token to create the pool for
  /// @param _token1 The token to create the pool for
  /// @param _fee The fee of the pool
  /// @param _sqrtPriceX96Launch The sqrt price of the pool
  /// @return pool The address of the pool
  function _createPool(IERC20 _token0, IERC20 _token1, uint24 _fee, uint160 _sqrtPriceX96Launch)
    internal
    virtual
    returns (IClPool pool);

  receive() external payable {}
}
