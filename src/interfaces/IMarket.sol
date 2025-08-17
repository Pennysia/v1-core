// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

/// @title IMarket
/// @notice Interface for the Pennysia Market contract handling pairs, liquidity, swaps, and more.
interface IMarket {
    /// @notice Error thrown when caller is not authorized.
    error forbidden();
    /// @notice Error thrown when pair does not exist.
    error pairNotFound();
    /// @notice Error thrown when sweep amount exceeds available.
    error excessiveSweep();
    /// @notice Error thrown when reserves fall below minimum.
    error minimumLiquidity();
    /// @notice Error thrown for invalid swap path.
    error invalidPath();

    /// @notice Structure representing a trading pair's reserves and oracle data.
    /// @param reserve0Long Long reserve of token0.
    /// @param reserve0Short Short reserve of token0.
    /// @param reserve1Long Long reserve of token1.
    /// @param reserve1Short Short reserve of token1.
    /// @param blockTimestampLast Last update timestamp.
    /// @param cbrtPriceX128CumulativeLast Cumulative cube-root price (scaled by 2^128).
    struct Pair {
        uint128 reserve0Long;
        uint128 reserve0Short;
        uint128 reserve1Long;
        uint128 reserve1Short;
        uint64 blockTimestampLast;
        uint192 cbrtPriceX128CumulativeLast; // cum. of cbrt(y/x * 10^128)*timeElapsed
    }

    /// @notice Emitted when a new pair is created.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param pairId Computed pair ID.
    event Create(address indexed token0, address indexed token1, uint256 pairId);

    /// @notice Emitted when liquidity is minted.
    /// @param sender Caller.
    /// @param to Recipient.
    /// @param pairId Pair ID.
    /// @param amount0 Token0 amount added.
    /// @param amount1 Token1 amount added.
    event Mint(address indexed sender, address indexed to, uint256 indexed pairId, uint256 amount0, uint256 amount1);

    /// @notice Emitted when liquidity is burned.
    /// @param sender Caller.
    /// @param to Recipient.
    /// @param pairId Pair ID.
    /// @param amount0 Token0 amount withdrawn.
    /// @param amount1 Token1 amount withdrawn.
    event Burn(address indexed sender, address indexed to, uint256 indexed pairId, uint256 amount0, uint256 amount1);

    /// @notice Emitted when excess tokens are swept.
    /// @param sender Caller (owner).
    /// @param to Recipients.
    /// @param tokens Tokens swept.
    /// @param amounts Amounts swept.
    event Sweep(address indexed sender, address[] to, address[] tokens, uint256[] amounts);

    /// @notice Emitted when a flash loan is executed.
    /// @param sender Caller.
    /// @param to Recipient.
    /// @param tokens Tokens loaned.
    /// @param amounts Amounts loaned.
    /// @param paybackAmounts Amounts to repay (with fee).
    event Flash(address indexed sender, address to, address[] tokens, uint256[] amounts, uint256[] paybackAmounts);

    /// @notice Emitted when a swap occurs.
    /// @param sender Caller.
    /// @param to Recipient.
    /// @param tokenIn Input token.
    /// @param tokenOut Output token.
    /// @param amountIn Input amount.
    /// @param amountOut Output amount.
    event Swap(
        address indexed sender,
        address indexed to,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    // Read-only functions
    /// @notice Retrieves pair data.
    /// @param pairId The pair ID.
    /// @return reserve0Long
    /// @return reserve0Short
    /// @return reserve1Long
    /// @return reserve1Short
    /// @return blockTimestampLast
    /// @return cbrtPriceX128CumulativeLast
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

    /// @notice Gets reserved balance for a token.
    /// @param token Token address.
    /// @return Balance.
    function tokenBalances(address token) external view returns (uint256);

    /// @notice Computes pair ID.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return pairId.
    function getPairId(address token0, address token1) external view returns (uint256);

    /// @notice Gets reserves for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return reserve0Long
    /// @return reserve0Short
    /// @return reserve1Long
    /// @return reserve1Short
    function getReserves(address token0, address token1)
        external
        view
        returns (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short);

    /// @notice Calculates sweepable amount for a token.
    /// @param token Token address.
    /// @return Amount.
    function getSweepable(address token) external view returns (uint256);

    /// @notice Sweeps excess tokens.
    /// @param tokens Tokens to sweep.
    /// @param amounts Amounts.
    /// @param to Recipients.
    function sweep(address[] calldata tokens, uint256[] calldata amounts, address[] calldata to) external;

    /// @notice Executes flash loan.
    /// @param to Recipient.
    /// @param tokens Tokens.
    /// @param amounts Amounts.
    function flash(address to, address[] calldata tokens, uint256[] calldata amounts) external;

    // State-changing functions
    /// @notice Creates/adds liquidity.
    /// @param to LP recipient.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0Long Amount of token0 long to add.
    /// @param amount0Short Amount of token0 short to add.
    /// @param amount1Long Amount of token1 long to add.
    /// @param amount1Short Amount of token1 short to add.
    /// @return pairId
    /// @return liquidity0Long
    /// @return liquidity0Short
    /// @return liquidity1Long
    /// @return liquidity1Short
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

    /// @notice Withdraws liquidity.
    /// @param to Recipient.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param liquidity0Long Amount of token0 long to burn.
    /// @param liquidity0Short Amount of token0 short to burn.
    /// @param liquidity1Long Amount of token1 long to burn.
    /// @param liquidity1Short Amount of token1 short to burn.
    /// @return pairId
    /// @return amount0
    /// @return amount1
    function withdrawLiquidity(
        address to,
        address token0,
        address token1,
        uint256 liquidity0Long,
        uint256 liquidity0Short,
        uint256 liquidity1Long,
        uint256 liquidity1Short
    ) external returns (uint256 pairId, uint256 amount0, uint256 amount1);

    /// @notice Performs swap.
    /// @param to Recipient.
    /// @param path Swap path.
    /// @param amountIn Input amount.
    /// @return amountOut Output amount.
    function swap(address to, address[] calldata path, uint256 amountIn) external returns (uint256 amountOut);

    /// @notice Sets new owner.
    /// @param _owner New owner address.
    function setOwner(address _owner) external;

    /// @notice Gets current owner.
    /// @return Owner address.
    function owner() external view returns (address);
}
