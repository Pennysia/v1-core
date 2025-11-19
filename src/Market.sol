// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {Liquidity} from "./abstracts/Liquidity.sol";
import {ReentrancyGuard} from "./abstracts/ReentrancyGuard.sol";
import {OwnerAction} from "./abstracts/OwnerAction.sol";

import {Callback} from "./libraries/Callback.sol";
import {Validation} from "./libraries/Validation.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Math} from "./libraries/Math.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {PairLibrary} from "./libraries/PairLibrary.sol";

import {IMarket} from "./interfaces/IMarket.sol";
import {IPayment} from "./interfaces/IPayment.sol";

contract Market is IMarket, Liquidity, ReentrancyGuard, OwnerAction {
    using SafeCast for uint256;

    mapping(address => mapping(address => Pair)) public override pairs;

    uint64 public override totalPairs;

    constructor() OwnerAction(msg.sender) {}

    receive() external payable {}

    //--------------------------------- Read-Only Functions ---------------------------------

    function getPrice(address token0, address token1) public view override returns (uint256 price) {
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);
        price = Math.fullMulDiv(reserve1Long + reserve1Short, PairLibrary.SCALE, reserve0Long + reserve0Short);
    }

    function getReserve(address token0, address token1)
        public
        view
        override
        returns (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short)
    {
        reserve0Long = pairs[token0][token1].reserve0Long;
        reserve0Short = pairs[token0][token1].reserve0Short;
        reserve1Long = pairs[token0][token1].reserve1Long;
        reserve1Short = pairs[token0][token1].reserve1Short;
    }

    function getTokenId(address token0, address token1) public view override returns (uint128 idLong, uint128 idShort) {
        idShort = pairs[token0][token1].poolId * 2;
        idLong = idShort - 1;
    }

    function getLiquidity(address token0, address token1)
        public
        view
        override
        returns (uint256 liquidityLong, uint256 liquidityShort)
    {
        (uint128 idLong, uint128 idShort) = getTokenId(token0, token1);
        liquidityLong = totalSupply[idLong];
        liquidityShort = totalSupply[idShort];
    }

    function getFee(address token0, address token1) public view override returns (uint256 fee0, uint256 fee1) {
        (uint128 idLong, uint128 idShort) = getTokenId(token0, token1);
        fee0 = totalVoteWeight[idLong] / totalSupply[idLong];
        fee1 = totalVoteWeight[idShort] / totalSupply[idShort];
    }

    //--------------------------------- Read-Write Functions ---------------------------------

    function setDeployer(address _deployer, address token0, address token1) external override {
        require(pairs[token0][token1].deployer == msg.sender, forbidden());
        pairs[token0][token1].deployer = _deployer;
        emit DeployerChanged(token0, token1, _deployer);
    }

    function flashloan(address to, address[] calldata tokens, uint256[] calldata amounts)
        external
        override
        nonReentrant
    {
        // 0.check inputs
        address callback = msg.sender;
        uint256 length = tokens.length;
        Validation.notThis(to);
        Validation.equalLengths(length, amounts.length);
        Validation.checkRedundantNative(tokens); // not allow duplicated native token input in the array

        // 1.record payback amounts and transfer tokens to user
        uint256[] memory paybackAmounts = new uint256[](length);
        uint256[] memory balancesBefore = new uint256[](length);

        for (uint256 i; i < length; i++) {
            paybackAmounts[i] = Math.fullMulDivUp(amounts[i], 1001, 1000); // fixed 0.1% fee (10 bps)
            TransferHelper.safeTransfer(tokens[i], to, amounts[i]);
            balancesBefore[i] = PairLibrary.getBalance(tokens[i]);
        }

        // 2.user performs actions and payback in the callback.
        Callback.tokenCallback(callback, to, tokens, balancesBefore, paybackAmounts);
        emit Flash(callback, to, tokens, amounts, paybackAmounts);
    }

    /// NOTE: fee-on-transfer tokens are NOT supported.
    /// NOTE: all amount0 and amount1 inputs here are permanently locked liquidity.
    function create(address deployer, address token0, address token1, uint256 amount0, uint256 amount1, uint256 fee)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint64 poolId)
    {
        // 0.check inputs
        Validation.notThis(deployer);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens

        Pair storage pair = pairs[token0][token1];
        require(pair.poolId == 0, pairAlreadyExists());

        poolId = totalPairs++; // this writes to totalPairs
        uint256 idShort = poolId * 2;
        uint256 idLong = idShort - 1;

        uint256 halfLiquidity = Math.sqrt(amount0 * amount1) >> 1;
        require(halfLiquidity > PairLibrary.MINIMUM_LIQUIDITY, notEnoughLiquidity());

        // 1.ask for payment
        IPayment(msg.sender)
            .requestToken(
                deployer,
                PairLibrary.createTokenArrays(token0, token1),
                PairLibrary.createAmountArrays(amount0, amount1)
            );

        // 2.mint liquidity and update storage
        _mint(address(0), idLong, halfLiquidity, fee); // locked liquidity
        _mint(address(0), idShort, halfLiquidity, fee); // locked liquidity

        // 3.update storages
        uint256 reserve0Long = amount0 >> 1;
        uint256 reserve1Long = amount1 >> 1;

        pair.poolId = poolId;
        pair.deployer = deployer;
        _updatePair(token0, token1, reserve0Long, amount0 - reserve0Long, reserve1Long, amount1 - reserve1Long);

        tokenBalances[token0] += amount0;
        tokenBalances[token1] += amount1;

        emit Create(token0, token1, deployer);
    }

    // NOTE: fee-on-transfer tokens are NOT supported.
    // NOTE: slippage tolerance is checked in the Router contract.
    // NOTE: if amount0 or amount1 is 0, liquidity output will become 0.
    function deposit(address to, address token0, address token1, uint256 liquidityLong, uint256 liquidityShort)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint256 amount0, uint256 amount1)
    {
        // 0.check inputs
        Validation.notThis(to);

        Pair storage pair = pairs[token0][token1];
        uint256 poolId = pair.poolId;
        require(poolId > 0, pairNotFound()); // revert if 1.pool does not exist, 2.token unsorted

        // 1.calculate amounts
        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);

        uint256 amount0Long = Math.fullMulDivUp(liquidityLong, reserve0Long, supplyLong);
        uint256 amount0Short = Math.fullMulDivUp(liquidityShort, reserve0Short, supplyShort);
        uint256 amount1Long = Math.fullMulDivUp(liquidityLong, reserve1Long, supplyLong);
        uint256 amount1Short = Math.fullMulDivUp(liquidityShort, reserve1Short, supplyShort);

        amount0 = amount0Long + amount0Short;
        amount1 = amount1Long + amount1Short;

        // 2.request a user payment
        IPayment(msg.sender)
            .requestToken(
                to, PairLibrary.createTokenArrays(token0, token1), PairLibrary.createAmountArrays(amount0, amount1)
            );

        // 3.mint liquidity tokens
        uint256 shortTokenId = poolId * 2;
        uint256 longTokenId = shortTokenId - 1;

        _mint(to, longTokenId, liquidityLong, 0);
        _mint(to, shortTokenId, liquidityShort, 0);

        // 4.update storages
        _updatePair(
            token0,
            token1,
            reserve0Long + amount0Long,
            reserve0Short + amount0Short,
            reserve1Long + amount1Long,
            reserve1Short + amount1Short
        );

        tokenBalances[token0] += amount0;
        tokenBalances[token1] += amount1;

        // 5.emit Mint event
        emit Mint(to, token0, token1, amount0, amount1, liquidityLong, liquidityShort);
    }

    function withdraw(
        address from,
        address to,
        address token0,
        address token1,
        uint256 liquidityLong,
        uint256 liquidityShort
    ) external override nonReentrant onlyRouter returns (uint256 amount0, uint256 amount1) {
        // 0.check inputs
        Validation.notThis(from);
        Validation.notThis(to);

        Pair storage pair = pairs[token0][token1];
        uint256 poolId = pair.poolId;
        require(poolId > 0, pairNotFound()); // revert if 1. pool does not exist 2.token unsorted

        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);

        // 1.calculate withdrawal amounts
        uint256 amount0Long = Math.fullMulDiv(liquidityLong, reserve0Long, supplyLong);
        uint256 amount0Short = Math.fullMulDiv(liquidityShort, reserve0Short, supplyShort);
        uint256 amount1Long = Math.fullMulDiv(liquidityLong, reserve1Long, supplyLong);
        uint256 amount1Short = Math.fullMulDiv(liquidityShort, reserve1Short, supplyShort);

        amount0 = amount0Long + amount0Short;
        amount1 = amount1Long + amount1Short;

        // 2.burn LP tokens
        uint256 shortTokenId = poolId * 2;
        uint256 longTokenId = shortTokenId - 1;
        _burn(from, longTokenId, liquidityLong);
        _burn(from, shortTokenId, liquidityShort);

        // 3.update storages
        _updatePair(
            token0,
            token1,
            reserve0Long - amount0Long,
            reserve0Short - amount0Short,
            reserve1Long - amount1Long,
            reserve1Short - amount1Short
        );

        tokenBalances[token0] -= amount0;
        tokenBalances[token1] -= amount1;

        // 4.transfer tokens to `to`
        TransferHelper.safeTransfer(token0, to, amount0);
        TransferHelper.safeTransfer(token1, to, amount1);

        // 5.emit Withdraw event
        emit Withdraw(from, to, token0, token1, amount0, amount1, liquidityLong, liquidityShort);
    }

    function lpSwap(address from, address to, address token0, address token1, bool longToShort, uint256 liquidityIn)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint256 liquidityOut)
    {
        // 0.check inputs
        Validation.notThis(from);
        Validation.notThis(to);

        uint256 poolId = pairs[token0][token1].poolId;
        require(poolId > 0, pairNotFound()); // revert if 1. pool does not exist 2.token unsorted

        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);

        // 1.calculate amounts and output liquidity based on direction
        if (longToShort) {
            uint256 amount0 = Math.fullMulDiv(liquidityIn, reserve0Long, supplyLong);
            uint256 amount1 = Math.fullMulDiv(liquidityIn, reserve1Long, supplyLong);
            liquidityOut = PairLibrary.min(
                Math.fullMulDiv(amount0, supplyShort, reserve0Short),
                Math.fullMulDiv(amount1, supplyShort, reserve1Short)
            );
            reserve0Long -= amount0;
            reserve0Short += amount0;
            reserve1Long -= amount1;
            reserve1Short += amount1;
        } else {
            uint256 amount0 = Math.fullMulDiv(liquidityIn, reserve0Short, supplyShort);
            uint256 amount1 = Math.fullMulDiv(liquidityIn, reserve1Short, supplyShort);
            liquidityOut = PairLibrary.min(
                Math.fullMulDiv(amount0, supplyLong, reserve0Long), Math.fullMulDiv(amount1, supplyLong, reserve1Long)
            );
            reserve0Short -= amount0;
            reserve0Long += amount0;
            reserve1Short -= amount1;
            reserve1Long += amount1;
        }

        // 2.burn input and mint output liquidity
        uint256 shortTokenId = poolId * 2;
        uint256 longTokenId = shortTokenId - 1;

        _burn(from, longToShort ? longTokenId : shortTokenId, liquidityIn);
        _mint(to, longToShort ? shortTokenId : longTokenId, liquidityOut, 0);

        // 3.update storages
        _updatePair(token0, token1, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

        emit LiquiditySwap(from, to, token0, token1, longToShort, liquidityIn, liquidityOut);
    }

    error invalidPath();

    function swap(address to, address[] memory path, uint256 amount)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint256 amountOut)
    {
        // 0.check inputs
        Validation.notThis(to);
        require(amount != 0);
        uint256 length = path.length;
        require(length >= 2, invalidPath());

        uint256 amountIn = amount;
        address tokenIn = path[0];

        for (uint256 i; i < length - 1; i++) {
            (address token0, address token1, bool zeroForOne) =
                path[i] < path[i + 1] ? (path[i], path[i + 1], true) : (path[i + 1], path[i], false);

            uint256 poolId = pairs[token0][token1].poolId;
            require(poolId > 0, pairNotFound()); // revert if 1. pool does not exist 2.token unsorted

            (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
                getReserve(token0, token1);

            uint256 reserveIn = zeroForOne ? (reserve0Long + reserve0Short) : (reserve1Long + reserve1Short);
            uint256 reserveOut = zeroForOne ? (reserve1Long + reserve1Short) : (reserve0Long + reserve0Short);

            uint256 newReserveIn = reserveIn + amountIn;
            uint256 newReserveOut = Math.fullMulDiv(reserveOut, reserveIn, newReserveIn);
            amountOut = reserveOut - newReserveOut;

            if (zeroForOne) {
                //update reserves long and short
            } else {
                //update reserves long and short
            }

            //write to update pairs
            //update tokenBalances and deplyerFee
        }

        //ask for payment
        //then transfer the token
        //emit Swap event
    }

    // function swap(address to, address[] memory path, uint256 amount)
    //     external
    //     override
    //     nonReentrant
    //     onlyRouter
    //     returns (uint256 amountOut)
    // {
    //     address callback = msg.sender;
    //     Validation.notThis(to);
    //     Validation.notZero(amount);
    //     uint256 length = path.length;
    //     require(length >= 2, invalidPath());

    //     uint256[] memory amountIn = new uint256[](1);
    //     amountIn[0] = amount;
    //     address[] memory tokenIn = new address[](1);
    //     tokenIn[0] = path[0];

    //     // For each hop in the path:
    //     for (uint256 i; i < length - 1; i++) {
    //         // Determine direction and reserves.
    //         (address token0, address token1, bool zeroForOne) =
    //             path[i] < path[i + 1] ? (path[i], path[i + 1], true) : (path[i + 1], path[i], false);

    //         uint256 pairId = getPairId(token0, token1); //require pre-sorting of tokens
    //         (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
    //             getReserves(pairId);

    //         require(reserve0Long > 0, pairNotFound());

    //         uint256 reserveIn = zeroForOne ? (reserve0Long + reserve0Short) : (reserve1Long + reserve1Short);
    //         uint256 reserveOut = zeroForOne ? (reserve1Long + reserve1Short) : (reserve0Long + reserve0Short);
    //         // Compute new reserves using constant product formula.
    //         uint256 newReserveIn = reserveIn + amount;
    //         uint256 newReserveOut = Math.fullMulDiv(reserveOut, reserveIn, newReserveIn);
    //         amountOut = reserveOut - newReserveOut;

    //         // Apply fees: adjust long/short splits.
    //         uint256 feeAmountOut = Math.divUp(amountOut * FEE, 1000); // won't overflow
    //         uint256 feeAmountIn = Math.divUp(amountIn[0] * FEE, 1000); // won't overflow

    //         if (zeroForOne) {
    //             // Scale output reserves and add fee to long.
    //             reserve1Long = Math.fullMulDiv(reserve1Long, newReserveOut, reserveOut);
    //             reserve1Short = newReserveOut - reserve1Long;
    //             reserve1Long += feeAmountOut; //100% fee goes to long positions of reserveOut

    //             // Scale input reserves and move fee from long to short.
    //             reserve0Long = Math.fullMulDiv(reserve0Long, newReserveIn, reserveIn);
    //             reserve0Short = newReserveIn - reserve0Long;
    //             if (reserve0Long > feeAmountIn) {
    //                 reserve0Long -= feeAmountIn;
    //                 reserve0Short += feeAmountIn;
    //             }
    //         } else {
    //             // Symmetric logic for the other direction.
    //             reserve0Long = Math.fullMulDiv(reserve0Long, newReserveOut, reserveOut);
    //             reserve0Short = newReserveOut - reserve0Long;
    //             reserve0Long += feeAmountOut; //100% fee goes to long positions of reserveOut

    //             reserve1Long = Math.fullMulDiv(reserve1Long, newReserveIn, reserveIn);
    //             reserve1Short = newReserveIn - reserve1Long;
    //             if (reserve1Long > feeAmountIn) {
    //                 reserve1Long -= feeAmountIn;
    //                 reserve1Short += feeAmountIn;
    //             }
    //         }
    //         amountOut -= feeAmountOut;
    //         amountIn[0] = amountOut; //chaining output as input for next swap

    //         _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

    //         (uint256 newBalance0, uint256 newBalance1) = zeroForOne
    //             ? (tokenBalances[token0] + amount, tokenBalances[token1] - amountOut)
    //             : (tokenBalances[token0] + amountOut, tokenBalances[token1] + amount);
    //         _updateBalance(token0, token1, newBalance0, newBalance1);
    //     }

    //     amountIn[0] = amount;
    //     uint256[] memory balancesBefore = new uint256[](1);
    //     balancesBefore[0] = PairLibrary.getBalance(path[0]);
    //     Callback.tokenCallback(callback, to, tokenIn, balancesBefore, amountIn); //user pays within this callback

    //     TransferHelper.safeTransfer(path[length - 1], to, amountOut); // transfer the output token to the user

    //     emit Swap(callback, to, path[0], path[length - 1], amount, amountOut);
    // }

    //--------------------------------- Private Functions ---------------------------------

    function _updatePair(
        address token0,
        address token1,
        uint256 reserve0Long,
        uint256 reserve0Short,
        uint256 reserve1Long,
        uint256 reserve1Short
    ) private {
        Pair storage pair = pairs[token0][token1];
        uint32 blockTimestamp = uint32(block.timestamp); // uint32 is enough for 136 years
        uint256 timeElapsed = blockTimestamp - pair.blockTimestampLast;
        if (timeElapsed > 0) {
            uint256 cbrtPrice = Math.cbrt(
                Math.fullMulDiv(reserve1Long + reserve1Short, PairLibrary.SCALE, reserve0Long + reserve0Short)
            );
            pair.reserve0Long = reserve0Long.safe128();
            pair.reserve0Short = reserve0Short.safe128();
            pair.reserve1Long = reserve1Long.safe128();
            pair.reserve1Short = reserve1Short.safe128();
            pair.cbrtPriceCumulativeLast += (cbrtPrice * timeElapsed);
            pair.blockTimestampLast = blockTimestamp;
        }
    }
}
