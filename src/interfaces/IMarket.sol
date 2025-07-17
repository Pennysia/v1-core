// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

interface IMarket {
    error forbidden();
    error pairNotFound();
    error excessiveSweep();
    error minimumLiquidity();
    error invalidPath();

    struct Pair {
        uint128 reserve0Long;
        uint128 reserve0Short;
        uint128 reserve1Long;
        uint128 reserve1Short;
        uint64 blockTimestampLast;
        uint192 cbrtPriceX128CumulativeLast; // cum. of cbrt(y/x * 10^128)*timeElapsed
    }

    event Create(address indexed token0, address indexed token1, uint256 pairId);
    event Mint(address indexed sender, address indexed to, uint256 indexed pairId, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, address indexed to, uint256 indexed pairId, uint256 amount0, uint256 amount1);
    event Sweep(address indexed sender, address[] to, address[] tokens, uint256[] amounts);
    event Flash(address indexed sender, address to, address[] tokens, uint256[] amounts, uint256[] paybackAmounts);
    event Swap(
        address indexed sender,
        address indexed to,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
}
