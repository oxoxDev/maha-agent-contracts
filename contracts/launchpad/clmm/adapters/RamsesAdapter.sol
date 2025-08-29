// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {BaseV3Adapter, IClPool, IERC20, SafeERC20} from "./BaseV3Adapter.sol";
import {IFreeUniV3LPLocker} from "contracts/interfaces/IFreeUniV3LPLocker.sol";

interface INonfungiblePositionManagerRamses {
  struct MintParams {
    address token0;
    address token1;
    uint24 fee;
    int24 tickLower;
    int24 tickUpper;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address recipient;
    uint256 deadline;
    uint256 veNFTTokenId;
  }

  function mint(MintParams calldata params)
    external
    payable
    returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IRamsesPoolFactory {
  function createPool(IERC20 _token0, IERC20 _token1, uint24 _fee, uint160 _sqrtPriceX96Launch)
    external
    returns (address pool);
}

contract RamsesAdapter is BaseV3Adapter {
  using SafeERC20 for IERC20;

  constructor(
    address _launchpad,
    address _clPoolFactory,
    address _swapRouter,
    address _WETH9,
    address _locker,
    address _nftPositionManager
  ) {
    __BaseV3Adapter_init(_launchpad, _WETH9, _locker, _swapRouter, _nftPositionManager, _clPoolFactory);
  }

  function _mint(IERC20 _token0, IERC20 _token1, int24 _tick0, int24 _tick1, uint24 _fee, uint256 _amount0)
    internal
    returns (uint256 tokenId)
  {
    _token0.safeTransferFrom(msg.sender, address(this), _amount0);
    _token0.approve(address(nftPositionManager), _amount0);

    // mint the position
    INonfungiblePositionManagerRamses.MintParams memory params = INonfungiblePositionManagerRamses.MintParams({
      token0: address(_token0),
      token1: address(_token1),
      fee: _fee,
      tickLower: _tick0,
      tickUpper: _tick1,
      amount0Desired: _amount0,
      amount1Desired: 0,
      amount0Min: 0,
      amount1Min: 0,
      recipient: _me,
      deadline: block.timestamp,
      veNFTTokenId: 0
    });

    (tokenId,,,) = INonfungiblePositionManagerRamses(address(nftPositionManager)).mint(params);
  }

  function _collectFees(uint256 _lockId) internal override returns (uint256 fee0, uint256 fee1) {
    (fee0, fee1) = IFreeUniV3LPLocker(locker).collect(_lockId, address(this), type(uint128).max, type(uint128).max);
  }

  function _createPool(IERC20 _token0, IERC20 _token1, uint24 _fee, uint160 _sqrtPriceX96Launch)
    internal
    virtual
    override
    returns (IClPool pool)
  {
    address _pool = IRamsesPoolFactory(address(clPoolFactory)).createPool(_token0, _token1, _fee, _sqrtPriceX96Launch);
    pool = IClPool(_pool);
  }

  function _mintAndLock(
    IERC20 _token0,
    IERC20 _token1,
    int24 _tick0,
    int24 _tick1,
    uint24 _fee,
    uint256 _amount0,
    uint256 _index
  ) internal override returns (uint256 lockId) {
    // mint the position
    uint256 tokenId = _mint(_token0, _token1, _tick0, _tick1, _fee, _amount0);

    // lock the liquidity forever; allow this contract to collect fees
    lockId = IFreeUniV3LPLocker(locker).nextLockId();
    nftPositionManager.safeTransferFrom(address(this), locker, tokenId);
    tokenToLockId[IERC20(_token0)][_index] = lockId;
  }

  function _mintAndBurn(IERC20 _token0, IERC20 _token1, int24 _tick0, int24 _tick1, uint24 _fee, uint256 _amount0)
    internal
    override
  {
    // mint the position
    uint256 tokenId = _mint(_token0, _token1, _tick0, _tick1, _fee, _amount0);

    // burn the position
    nftPositionManager.transferFrom(address(this), address(0), tokenId);
  }
}
