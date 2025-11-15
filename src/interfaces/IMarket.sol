// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.30;

/// @title IMarket
/// @notice Interface for the Pennysia Market contract handling pairs, liquidity, swaps, and more.
interface IMarket {
    /// @notice Error thrown when pair does not exist.
    error pairNotFound();

    /// @notice Error thrown for invalid swap path.
    error invalidPath();

    /// @notice Error thrown when pair already exists.
    error pairAlreadyExists();

    /// @notice Error thrown when not enough liquidity.
    error notEnoughLiquidity();

    struct Pair {
        uint128 poolId; // ---> update on create a new pool
        uint128 divider;
        uint128 reserve0;
        uint128 reserve1;
        address deployer; // done---> update on create a new pool or change by exisiting deployer
        uint96 blockTimestampLast;
        uint256 cbrtPriceCumulativeLast; // cum. of (cbrt(y/x * uint128.max))*timeElapsed
    }

    /// @notice Emitted when deployer is updated.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param deployer new deployer address.
    event DeployerChanged(address indexed token0, address indexed token1, address indexed deployer);

    /// @notice Emitted when a flash loan is executed.
    /// @param caller Caller.
    /// @param to Recipient.
    /// @param tokens Tokens loaned.
    /// @param amounts Amounts loaned.
    /// @param paybackAmounts Amounts to repay (with fee).
    event Flash(address indexed caller, address to, address[] tokens, uint256[] amounts, uint256[] paybackAmounts);

    /// @notice Emitted when a new pair is created.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param deployer Deployer address.
    event Create(address indexed token0, address indexed token1, address indexed deployer);

    /// @notice Emitted when liquidity is minted.
    /// @param to Recipient.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Token0 amount.
    /// @param amount1 Token1 amount.
    /// @param longLiquidity Long liquidity amount.
    /// @param shortLiquidity Short liquidity amount.
    event Mint(
        address indexed to,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 longLiquidity,
        uint256 shortLiquidity
    );

    // /// @notice Emitted when liquidity is burned.
    // /// @param sender Caller.
    // /// @param to Recipient.
    // /// @param pairId Pair ID.
    // /// @param amount0 Token0 amount withdrawn.
    // /// @param amount1 Token1 amount withdrawn.
    // event Burn(address indexed sender, address indexed to, uint256 indexed pairId, uint256 amount0, uint256 amount1);

    // /// @notice Emitted when liquidity is swapped.
    // /// @param sender Caller.
    // /// @param to Recipient.
    // /// @param pairId Pair ID.
    // /// @param longToShort0 Whether to swap long to short for token0.
    // /// @param liquidity0 Amount of token0 liquidity to swap.
    // /// @param liquidityOut0 Amount of token0 liquidity out.
    // /// @param longToShort1 Whether to swap long to short for token1.
    // /// @param liquidity1 Amount of token1 liquidity to swap.
    // /// @param liquidityOut1 Amount of token1 liquidity out.
    // /// @param longToShort0 Whether to swap long to short for token0.
    // event LiquiditySwap(
    //     address indexed sender,
    //     address indexed to,
    //     uint256 indexed pairId,
    //     bool longToShort0,
    //     uint256 liquidity0,
    //     uint256 liquidityOut0,
    //     bool longToShort1,
    //     uint256 liquidity1,
    //     uint256 liquidityOut1
    // );

    // /// @notice Emitted when a swap occurs.
    // /// @param sender Caller.
    // /// @param to Recipient.
    // /// @param tokenIn Input token.
    // /// @param tokenOut Output token.
    // /// @param amountIn Input amount.
    // /// @param amountOut Output amount.
    // event Swap(
    //     address indexed sender,
    //     address indexed to,
    //     address tokenIn,
    //     address tokenOut,
    //     uint256 amountIn,
    //     uint256 amountOut
    // );

    //--------------------------------- Read-Only Functions ---------------------------------

    /// @notice Gets pair data.
    /// @return poolId liquidity pool ID.
    /// @return divider liquidity divder between long and short
    /// @return reserve0 reserve of token0 .
    /// @return reserve1 rserve of token1.
    /// @return deployer The pool deployer address
    /// @return blockTimestampLast The block timestamp of the last update.
    /// @return cbrtPriceCumulativeLast The cumulative cbrtTWAP price of the pool.
    function pairs(address token0, address token1)
        external
        view
        returns (
            uint128 poolId,
            uint128 divider,
            uint128 reserve0,
            uint128 reserve1,
            address deployer,
            uint96 blockTimestampLast,
            uint256 cbrtPriceCumulativeLast
        );

    /// @notice Gets total number of pairs.
    /// @return Total number of pairs.
    function totalPairs() external view returns (uint256);

    /// @notice Gets price of a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return price of the pair(token0/token1) scaled by uint128.max
    function getPrice(address token0, address token1) external view returns (uint256 price);

    /// @notice Gets token reserves for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    function getReserve(address token0, address token1) external view returns (uint256 reserve0, uint256 reserve1);

    /// @notice Gets directional reserves for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return reserve0Long reserve of token0 in long direction.
    /// @return reserve0Short reserve of token0 in short direction.
    /// @return reserve1Long reserve of token1 in long direction.
    /// @return reserve1Short reserve of token1 in short direction.
    function getDirectionalReserve(address token0, address token1)
        external
        view
        returns (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short);

    /// @notice Gets LP token IDs for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return idLong Long token ID.
    /// @return idShort Short token ID.
    function getTokenId(address token0, address token1) external view returns (uint128 idLong, uint128 idShort);

    /// @notice Gets LP token liquidity for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return liquidityLong Long token liquidity.
    /// @return liquidityShort Short token liquidity.
    function getLiquidity(address token0, address token1)
        external
        view
        returns (uint256 liquidityLong, uint256 liquidityShort);

    /// @notice Gets LP token fee for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return fee0 Long token fee.
    /// @return fee1 Short token fee.
    function getFee(address token0, address token1) external view returns (uint256 fee0, uint256 fee1);

    //--------------------------------- Read-Write Functions ---------------------------------

    /// @notice Sets deployer for a pair.
    /// @param _deployer Deployer address.
    /// @param token0 First token.
    /// @param token1 Second token.
    function setDeployer(address _deployer, address token0, address token1) external;

    /// @notice Executes flash loan.
    /// @param to Recipient.
    /// @param tokens Tokens.
    /// @param amounts Amounts.
    function flashloan(address to, address[] calldata tokens, uint256[] calldata amounts) external;

    /// @notice Creates/adds liquidity.
    /// @param to LP recipient.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Amount of token0 to add.
    /// @param amount1 Amount of token1 to add.
    /// @param fee Fee.
    /// @return poolId Pool ID.
    function create(address to, address token0, address token1, uint256 amount0, uint256 amount1, uint256 fee)
        external
        returns (uint256 poolId);

    /// @notice Deposits liquidity.
    /// @param to LP recipient.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param liquidityLong Amount of long liquidity to deposit.
    /// @param liquidityShort Amount of short liquidity to deposit.
    /// @return amount0Required Amount of token0 required.
    /// @return amount1Required Amount of token1 required.
    function deposit(address to, address token0, address token1, uint256 liquidityLong, uint256 liquidityShort)
        external
        returns (uint256 amount0Required, uint256 amount1Required);

    // // State-changing functions
    // /// @notice Creates/adds liquidity.
    // /// @param to LP recipient.
    // /// @param token0 First token.
    // /// @param token1 Second token.
    // /// @param amount0Long Amount of token0 long to add.
    // /// @param amount0Short Amount of token0 short to add.
    // /// @param amount1Long Amount of token1 long to add.
    // /// @param amount1Short Amount of token1 short to add.
    // /// @return pairId
    // /// @return liquidity0Long
    // /// @return liquidity0Short
    // /// @return liquidity1Long
    // /// @return liquidity1Short
    // function createLiquidity(
    //     address to,
    //     address token0,
    //     address token1,
    //     uint256 amount0Long,
    //     uint256 amount0Short,
    //     uint256 amount1Long,
    //     uint256 amount1Short
    // )
    //     external
    //     returns (
    //         uint256 pairId,
    //         uint256 liquidity0Long,
    //         uint256 liquidity0Short,
    //         uint256 liquidity1Long,
    //         uint256 liquidity1Short
    //     );

    // /// @notice Withdraws liquidity.
    // /// @param to Recipient.
    // /// @param token0 First token.
    // /// @param token1 Second token.
    // /// @param liquidity0Long Amount of token0 long to burn.
    // /// @param liquidity0Short Amount of token0 short to burn.
    // /// @param liquidity1Long Amount of token1 long to burn.
    // /// @param liquidity1Short Amount of token1 short to burn.
    // /// @return pairId
    // /// @return amount0
    // /// @return amount1
    // function withdrawLiquidity(
    //     address to,
    //     address token0,
    //     address token1,
    //     uint256 liquidity0Long,
    //     uint256 liquidity0Short,
    //     uint256 liquidity1Long,
    //     uint256 liquidity1Short
    // ) external returns (uint256 pairId, uint256 amount0, uint256 amount1);

    // /// @notice Performs liquidity swap.
    // /// @param to Recipient.
    // /// @param token0 First token.
    // /// @param token1 Second token.
    // /// @param longToShort0 Whether to swap long to short for token0.
    // /// @param liquidity0 Amount of token0 liquidity to swap.
    // /// @param longToShort1 Whether to swap long to short for token1.
    // /// @param liquidity1 Amount of token1 liquidity to swap.
    // /// @return pairId The pair ID.
    // /// @return liquidityOut0 Amount of token0 liquidity out.
    // /// @return liquidityOut1 Amount of token1 liquidity out.
    // function lpSwap(
    //     address to,
    //     address token0,
    //     address token1,
    //     bool longToShort0,
    //     uint256 liquidity0,
    //     bool longToShort1,
    //     uint256 liquidity1
    // ) external returns (uint256 pairId, uint256 liquidityOut0, uint256 liquidityOut1);

    // /// @notice Performs swap.
    // /// @param to Recipient.
    // /// @param path Swap path.
    // /// @param amountIn Input amount.
    // /// @return amountOut Output amount.
    // function swap(address to, address[] calldata path, uint256 amountIn) external returns (uint256 amountOut);
}
