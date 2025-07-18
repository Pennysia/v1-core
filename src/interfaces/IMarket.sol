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

    // Read-only functions
    function pairs(uint256 pairId)
        external
        view
        returns (
            uint128 reserve0Long,
            uint128 reserve0Short,
            uint128 reserve1Long,
            uint128 reserve1Short,
            uint64 blockTimestampLast,
            uint192 cbrtPriceX128CumulativeLast
        );

    function tokenBalances(address token) external view returns (uint256);

    function getPairId(address token0, address token1) external view returns (uint256);

    function getReserves(address token0, address token1)
        external
        view
        returns (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short);

    function getSweepable(address token) external view returns (uint256);

    function sweep(address[] calldata tokens, uint256[] calldata amounts, address[] calldata to) external;

    function flash(address to, address[] calldata tokens, uint256[] calldata amounts) external;

    // State-changing functions
    function createLiquidity(
        address to,
        address token0,
        address token1,
        uint256 amount0Long,
        uint256 amount0Short,
        uint256 amount1Long,
        uint256 amount1Short
    )
        external
        returns (
            uint256 pairId,
            uint256 liquidity0Long,
            uint256 liquidity0Short,
            uint256 liquidity1Long,
            uint256 liquidity1Short
        );

    function withdrawLiquidity(
        address to,
        address token0,
        address token1,
        uint256 liquidity0Long,
        uint256 liquidity0Short,
        uint256 liquidity1Long,
        uint256 liquidity1Short
    ) external returns (uint256 pairId, uint256 amount0, uint256 amount1);

    function swap(address to, address[] calldata path, uint256 amountIn) external returns (uint256 amountOut);

    function setOwner(address _owner) external;

    function owner() external view returns (address);
}
