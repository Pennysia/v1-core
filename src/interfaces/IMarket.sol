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
        uint128 reserve0Long;
        uint128 reserve0Short;
        uint128 reserve1Long;
        uint128 reserve1Short;
        uint256 cbrtPriceCumulativeLast; // cum. of (cbrt(y/x * uint128.max))*timeElapsed
        uint32 blockTimestampLast;
        uint64 poolId; // update on create a new pool
        address deployer; // update on create a new pool or change by exisiting deployer
        uint128 deployerFee0;
        uint128 deployerFee1;
    }

    /// @notice Emitted when deployer is updated.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param deployer new deployer address.
    event DeployerChanged(address indexed token0, address indexed token1, address indexed deployer);

    /// @notice Emitted when deployer fee is claimed.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Token0 amount.
    /// @param amount1 Token1 amount.
    /// @param recipient Recipient address.
    event DeployerFeeClaimed(
        address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, address indexed recipient
    );

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
    /// @param payer Payer address.
    /// @param recipient Recipient address.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Token0 amount.
    /// @param amount1 Token1 amount.
    /// @param longLiquidity Long liquidity amount.
    /// @param shortLiquidity Short liquidity amount.
    event Mint(
        address indexed payer,
        address recipient,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 longLiquidity,
        uint256 shortLiquidity
    );

    /// @notice Emitted when liquidity is withdrawn.
    /// @param payer Payer address
    /// @param recipient Recipient address
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Token0 amount.
    /// @param amount1 Token1 amount.
    /// @param longLiquidity Long liquidity amount.
    /// @param shortLiquidity Short liquidity amount.
    event Withdraw(
        address indexed payer,
        address recipient,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 longLiquidity,
        uint256 shortLiquidity
    );

    /// @notice Emitted when liquidity is swapped.
    /// @param payer Payer address.
    /// @param recipient Recipient address.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param longToShort Whether to swap long to short.
    /// @param liquidityIn Input liquidity amount.
    /// @param liquidityOut Output liquidity amount.
    event LiquiditySwap(
        address indexed payer,
        address recipient,
        address indexed token0,
        address indexed token1,
        bool longToShort,
        uint256 liquidityIn,
        uint256 liquidityOut
    );

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
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return reserve0Long reserve of token0 in long direction.
    /// @return reserve0Short reserve of token0 in short direction.
    /// @return reserve1Long reserve of token1 in long direction.
    /// @return reserve1Short reserve of token1 in short direction.
    /// @return cbrtPriceCumulativeLast cumulative cbrtTWAP price of the pool.
    /// @return blockTimestampLast The block timestamp of the last update.
    /// @return poolId liquidity pool ID.
    /// @return deployer The pool deployer address
    /// @return deployerFee0 The pool deployer fee for token0.
    /// @return deployerFee1 The pool deployer fee for token1.
    function pairs(address token0, address token1)
        external
        view
        returns (
            uint128 reserve0Long,
            uint128 reserve0Short,
            uint128 reserve1Long,
            uint128 reserve1Short,
            uint256 cbrtPriceCumulativeLast,
            uint32 blockTimestampLast,
            uint64 poolId,
            address deployer,
            uint128 deployerFee0,
            uint128 deployerFee1
        );

    /// @notice Gets total number of pairs.
    /// @return Total number of pairs.
    function totalPairs() external view returns (uint64);

    /// @notice Gets price of a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return price of the pair(token0/token1) scaled by uint128.max
    function getPrice(address token0, address token1) external view returns (uint256 price);

    /// @notice Gets token reserves for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return reserve0Long reserve of token0 in long direction.
    /// @return reserve0Short reserve of token0 in short direction.
    /// @return reserve1Long reserve of token1 in long direction.
    /// @return reserve1Short reserve of token1 in short direction.
    function getReserve(address token0, address token1)
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
    /// @return feeLong fee voted by long liquidity providers
    /// @return feeShort fee voted by short liquidity providers
    function getFee(address token0, address token1) external view returns (uint256 feeLong, uint256 feeShort);

    //--------------------------------- Read-Write Functions ---------------------------------

    /// @notice Sets deployer for a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param _deployer Deployer address.
    function setDeployer(address token0, address token1, address _deployer) external;

    /// @notice Claims deployer fee.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param recipient Recipient address.
    function claimDeployerFee(address token0, address token1, address recipient) external;

    /// @notice Executes flash loan.
    /// @param payer Payer address.
    /// @param recipient Recipient address.
    /// @param tokens Tokens.
    /// @param amounts Amounts.
    function flashloan(address payer, address recipient, address[] calldata tokens, uint256[] calldata amounts) external;

    /// @notice Creates/adds liquidity.
    /// @param payer Payer address.
    /// @param deployer Deployer address.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0 Amount of token0 to add.
    /// @param amount1 Amount of token1 to add.
    /// @param fee Fee.
    /// @return poolId Pool ID.
    function createPool(
        address payer,
        address deployer,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 fee
    ) external returns (uint64 poolId);

    /// @notice Manages liquidity.
    /// @param payer LP sender address.
    /// @param recipient LP recipient address.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param liquidityLong Amount of long liquidity to deposit.
    /// @param liquidityShort Amount of short liquidity to deposit.
    /// @param mintOrNot Whether to mint or burn liquidity.
    /// @return amount0 Amount of token0 required.
    /// @return amount1 Amount of token1 required.
    function manageLiquidity(
        address payer,
        address recipient,
        address token0,
        address token1,
        uint256 liquidityLong,
        uint256 liquidityShort,
        bool mintOrNot
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swaps liquidity.
    /// @param payer LP sender address.
    /// @param recipeint Recipient address.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param longToShort Whether to swap long to short or short to long.
    /// @param liquidityIn Amount of liquidity to swap.
    /// @return liquidityOut Amount of liquidity swapped.
    function swapLiquidity(
        address payer,
        address recipeint,
        address token0,
        address token1,
        bool longToShort,
        uint256 liquidityIn
    ) external returns (uint256 liquidityOut);

    // /// @notice Swaps tokens.
    // /// @param payer Payer address.
    // /// @param recipient Recipient address.
    // /// @param path Swap path.
    // /// @param amount Amount of token to swap.
    // /// @return amountOut Amount of token swapped.
    // function swap(address payer, address recipient, address[] memory path, uint256 amount)
    //     external
    //     returns (uint256 amountOut);
}
