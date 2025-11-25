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

    function getFee(address token0, address token1) public view override returns (uint256 feeLong, uint256 feeShort) {
        (uint128 idLong, uint128 idShort) = getTokenId(token0, token1);
        feeLong = totalVoteWeight[idLong] / totalSupply[idLong];
        feeShort = totalVoteWeight[idShort] / totalSupply[idShort];
    }

    //--------------------------------- Read-Write Functions ---------------------------------

    function flashloan(address payer, address receipient, address[] calldata tokens, uint256[] calldata amounts)
        external
        override
        nonReentrant
    {
        // 0.check inputs
        address callback = msg.sender;
        uint256 length = tokens.length;
        Validation.equalLengths(length, amounts.length);
        Validation.checkRedundantNative(tokens); // not allow duplicated native token input in the array

        // 1.record payback amounts and transfer tokens to user
        uint256[] memory paybackAmounts = new uint256[](length);
        uint256[] memory balancesBefore = new uint256[](length);

        for (uint256 i; i < length; i++) {
            paybackAmounts[i] = (amounts[i] * 1001) / 1000; // fixed 0.1% fee (10 bps)
            TransferHelper.safeTransfer(tokens[i], receipient, amounts[i]);
            balancesBefore[i] = PairLibrary.getBalance(tokens[i]);
        }

        // 2.user performs actions and payback in the callback.
        Callback.tokenCallback(callback, payer, tokens, balancesBefore, paybackAmounts);
        emit Flash(payer, receipient, tokens, amounts, paybackAmounts);
    }

    /// NOTE: fee-on-transfer tokens are NOT supported.
    /// NOTE: all amount0 and amount1 inputs here are permanently locked liquidity.
    function createPool(
        address payer,
        address deployer,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 fee
    ) external override nonReentrant onlyRouter returns (uint64 poolId) {
        // 0.check inputs
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
                payer, PairLibrary.createTokenArrays(token0, token1), PairLibrary.createAmountArrays(amount0, amount1)
            );

        // 2.mint liquidity and update storage
        _mint(address(0), idLong, halfLiquidity, fee); // locked liquidity
        _mint(address(0), idShort, halfLiquidity, fee); // locked liquidity

        // 3.update storages
        uint256 reserve0Long = amount0 >> 1;
        uint256 reserve1Long = amount1 >> 1;

        pair.poolId = poolId;
        pair.deployer = deployer;
        _updatePair(token0, token1, reserve0Long, amount0 - reserve0Long, reserve1Long, amount1 - reserve1Long, 0, 0);

        tokenBalances[token0] += amount0;
        tokenBalances[token1] += amount1;

        emit Create(token0, token1, deployer);
    }

    // NOTE: fee-on-transfer tokens are NOT supported.
    // NOTE: slippage tolerance is checked in the Router contract.
    // NOTE: if amount0 or amount1 is 0, liquidity output will become 0.
    function manageLiquidity(
        address payer,
        address recipient,
        address token0,
        address token1,
        uint256 liquidityLong,
        uint256 liquidityShort,
        bool mintOrNot
    ) external override nonReentrant onlyRouter returns (uint256 amount0, uint256 amount1) {
        // 0.check inputs
        Pair storage pair = pairs[token0][token1];
        uint256 poolId = pair.poolId;
        require(poolId > 0, pairNotFound()); // revert if 1.pool does not exist, 2.token unsorted
        uint256 shortTokenId = poolId * 2;
        uint256 longTokenId = shortTokenId - 1;

        // 1.calculate amounts and handle mint/withdraw
        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);

        uint256 amount0Long = (liquidityLong * reserve0Long) / supplyLong;
        uint256 amount0Short = (liquidityShort * reserve0Short) / supplyShort;
        uint256 amount1Long = (liquidityLong * reserve1Long) / supplyLong;
        uint256 amount1Short = (liquidityShort * reserve1Short) / supplyShort;

        if (mintOrNot) {
            // Calculate total amounts for mint
            amount0 = amount0Long + amount0Short;
            amount1 = amount1Long + amount1Short;

            // Request user payment
            IPayment(msg.sender)
                .requestToken(
                    payer,
                    PairLibrary.createTokenArrays(token0, token1),
                    PairLibrary.createAmountArrays(amount0, amount1)
                );

            // Mint liquidity tokens and update reserves
            _mint(recipient, longTokenId, liquidityLong, 0);
            _mint(recipient, shortTokenId, liquidityShort, 0);

            reserve0Long += amount0Long;
            reserve0Short += amount0Short;
            reserve1Long += amount1Long;
            reserve1Short += amount1Short;

            tokenBalances[token0] += amount0;
            tokenBalances[token1] += amount1;

            // update storages
            _updatePair(token0, token1, reserve0Long, reserve0Short, reserve1Long, reserve1Short, 0, 0);
            emit Mint(payer, recipient, token0, token1, amount0, amount1, liquidityLong, liquidityShort);
        } else {
            // Burn LP tokens
            _burn(payer, longTokenId, liquidityLong);
            _burn(payer, shortTokenId, liquidityShort);

            // Process withdrawal with fees
            (
                uint256 totalFee0,
                uint256 totalFee1,
                uint256 lpFee0Long,
                uint256 lpFee0Short,
                uint256 lpFee1Long,
                uint256 lpFee1Short,
                uint256 deployerFee0,
                uint256 deployerFee1
            ) = _distributeFees(
                token0,
                token1,
                longTokenId,
                shortTokenId,
                amount0Long,
                amount0Short,
                amount1Long,
                amount1Short,
                supplyLong,
                supplyShort
            );

            // Calculate final user amounts
            amount0 = (amount0Long + amount0Short) - totalFee0;
            amount1 = (amount1Long + amount1Short) - totalFee1;

            // Update reserves (keep LP fees) and token balances
            reserve0Long -= (amount0Long - lpFee0Long);
            reserve0Short -= (amount0Short - lpFee0Short);
            reserve1Long -= (amount1Long - lpFee1Long);
            reserve1Short -= (amount1Short - lpFee1Short);

            // Update token balances (Keep LP fees + deployer fees)
            tokenBalances[token0] -= (amount0 + (totalFee0 - lpFee0Long - lpFee0Short - deployerFee0));
            tokenBalances[token1] -= (amount1 + (totalFee1 - lpFee1Long - lpFee1Short - deployerFee1));

            // Transfer tokens to recipient
            TransferHelper.safeTransfer(token0, recipient, amount0);
            TransferHelper.safeTransfer(token1, recipient, amount1);

            // update storages
            _updatePair(
                token0, token1, reserve0Long, reserve0Short, reserve1Long, reserve1Short, deployerFee0, deployerFee1
            );
            emit Withdraw(payer, recipient, token0, token1, amount0, amount1, liquidityLong, liquidityShort);
        }
    }

    function swapLiquidity(
        address payer,
        address recipient,
        address token0,
        address token1,
        bool longToShort,
        uint256 liquidityIn
    ) external override nonReentrant onlyRouter returns (uint256 liquidityOut) {
        // 0.check inputs
        uint256 poolId = pairs[token0][token1].poolId;
        require(poolId > 0, pairNotFound()); // revert if 1. pool does not exist 2.token unsorted
        uint256 shortTokenId = poolId * 2;
        uint256 longTokenId = shortTokenId - 1;

        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getReserve(token0, token1);

        // 1.calculate amounts and apply fees to liquidityIn
        uint256 amount0Long;
        uint256 amount0Short;
        uint256 amount1Long;
        uint256 amount1Short;

        if (longToShort) {
            amount0Long = (liquidityIn * reserve0Long) / supplyLong;
            amount1Long = (liquidityIn * reserve1Long) / supplyLong;
        } else {
            amount0Short = (liquidityIn * reserve0Short) / supplyShort;
            amount1Short = (liquidityIn * reserve1Short) / supplyShort;
        }

        // Apply fee distribution to the input amounts
        (
            uint256 totalFee0,
            uint256 totalFee1,
            uint256 lpFee0Long,
            uint256 lpFee0Short,
            uint256 lpFee1Long,
            uint256 lpFee1Short,
            uint256 deployerFee0,
            uint256 deployerFee1
        ) = _distributeFees(
            token0,
            token1,
            longTokenId,
            shortTokenId,
            amount0Long,
            amount0Short,
            amount1Long,
            amount1Short,
            supplyLong,
            supplyShort
        );

        // Calculate net amounts, output liquidity, and update reserves
        uint256 netAmount0 = (amount0Long + amount0Short) - totalFee0;
        uint256 netAmount1 = (amount1Long + amount1Short) - totalFee1;

        if (longToShort) {
            liquidityOut =
                PairLibrary.min((netAmount0 * supplyShort) / reserve0Short, (netAmount1 * supplyShort) / reserve1Short);
            reserve0Long -= (amount0Long - lpFee0Long);
            reserve0Short += netAmount0;
            reserve1Long -= (amount1Long - lpFee1Long);
            reserve1Short += netAmount1;
            _burn(payer, longTokenId, liquidityIn);
            _mint(recipient, shortTokenId, liquidityOut, 0);
        } else {
            liquidityOut =
                PairLibrary.min((netAmount0 * supplyLong) / reserve0Long, (netAmount1 * supplyLong) / reserve1Long);
            reserve0Long += netAmount0;
            reserve0Short -= (amount0Short - lpFee0Short);
            reserve1Long += netAmount1;
            reserve1Short -= (amount1Short - lpFee1Short);
            _burn(payer, shortTokenId, liquidityIn);
            _mint(recipient, longTokenId, liquidityOut, 0);
        }

        // Update token balances (deduct net protocol fees)
        tokenBalances[token0] -= (totalFee0 - lpFee0Long - lpFee0Short - deployerFee0);
        tokenBalances[token1] -= (totalFee1 - lpFee1Long - lpFee1Short - deployerFee1);

        // 3.update storages
        _updatePair(
            token0, token1, reserve0Long, reserve0Short, reserve1Long, reserve1Short, deployerFee0, deployerFee1
        );

        emit LiquiditySwap(payer, recipient, token0, token1, longToShort, liquidityIn, liquidityOut);
    }

    function swap(address payer, address recipient, address[] memory path, uint256 amount)
        external
        nonReentrant
        onlyRouter
        returns (uint256 amountOut)
    {
        // 0.check inputs
        uint256 length = path.length;
        require(length >= 2, invalidPath());

        address tokenIn = path[0];
        address tokenOut = path[length - 1];
        uint256 amountIn = amount;

        for (uint256 i; i < length - 1; i++) {
            amountIn = _processSwapHop(path[i], path[i + 1], amountIn);
            // Chain output as input for next swap
        }

        amountOut = amountIn;

        // Request payment for the initial input amount
        address[] memory paymentTokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        paymentTokens[0] = tokenIn;
        amounts[0] = amount;
        IPayment(msg.sender).requestToken(payer, paymentTokens, amounts);

        // transfer output token
        TransferHelper.safeTransfer(tokenOut, recipient, amountOut);

        // Emit swap event
        emit Swap(payer, recipient, tokenIn, tokenOut, amount, amountOut);
    }

    //--------------------------------- Private Functions ---------------------------------

    function _updatePair(
        address token0,
        address token1,
        uint256 reserve0Long,
        uint256 reserve0Short,
        uint256 reserve1Long,
        uint256 reserve1Short,
        uint256 deployerFee0,
        uint256 deployerFee1
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
            pair.deployerFee0 += deployerFee0.safe128();
            pair.deployerFee1 += deployerFee1.safe128();
        }
    }

    /// @dev Process withdrawal fees and return user amounts, protocol fees, and LP fees
    function _distributeFees(
        address token0,
        address token1,
        uint256 longTokenId,
        uint256 shortTokenId,
        uint256 amount0Long,
        uint256 amount0Short,
        uint256 amount1Long,
        uint256 amount1Short,
        uint256 supplyLong,
        uint256 supplyShort
    )
        private
        returns (
            uint256 totalFee0,
            uint256 totalFee1,
            uint256 lpFee0Long,
            uint256 lpFee0Short,
            uint256 lpFee1Long,
            uint256 lpFee1Short,
            uint256 deployerFee0,
            uint256 deployerFee1
        )
    {
        // Get fee rates
        (uint256 feeLong, uint256 feeShort) = getFee(token0, token1);

        // Calculate total fees
        uint256 totalFee0Long = (amount0Long * feeLong) / 100000;
        uint256 totalFee0Short = (amount0Short * feeShort) / 100000;
        uint256 totalFee1Long = (amount1Long * feeLong) / 100000;
        uint256 totalFee1Short = (amount1Short * feeShort) / 100000;

        totalFee0 = totalFee0Long + totalFee0Short;
        totalFee1 = totalFee1Long + totalFee1Short;

        // Calculate protocol fees (20% of total)
        uint256 protocolFee0Long = totalFee0Long / 5;
        uint256 protocolFee0Short = totalFee0Short / 5;
        uint256 protocolFee1Long = totalFee1Long / 5;
        uint256 protocolFee1Short = totalFee1Short / 5;

        lpFee0Long = totalFee0Long - protocolFee0Long;
        lpFee0Short = totalFee0Short - protocolFee0Short;
        lpFee1Long = totalFee1Long - protocolFee1Long;
        lpFee1Short = totalFee1Short - protocolFee1Short;

        if (!feeSwitch) {
            Pair storage pair = pairs[token0][token1];
            address deployer = pair.deployer;
            uint256 deployerLiquidityLong = balanceOf[deployer][longTokenId];
            uint256 deployerLiquidityShort = balanceOf[deployer][shortTokenId];

            // Deployer gets proportional share of half the protocol fees
            deployerFee0 = ((deployerLiquidityLong * protocolFee0Long >> 1) / supplyLong)
                + ((deployerLiquidityShort * protocolFee0Short >> 1) / supplyShort);
            deployerFee1 = ((deployerLiquidityLong * protocolFee1Long >> 1) / supplyLong)
                + ((deployerLiquidityShort * protocolFee1Short >> 1) / supplyShort);

            pair.deployerFee0 += deployerFee0.safe128();
            pair.deployerFee1 += deployerFee1.safe128();
        }
    }

    //--------------------------------- Deployer Functions ---------------------------------

    function setDeployer(address token0, address token1, address _deployer) external override {
        require(pairs[token0][token1].deployer == msg.sender, forbidden());
        pairs[token0][token1].deployer = _deployer;
        emit DeployerChanged(token0, token1, _deployer);
    }

    function claimDeployerFee(address token0, address token1, address recipient) external override nonReentrant {
        require(pairs[token0][token1].deployer == msg.sender, forbidden());
        uint256 fee0 = pairs[token0][token1].deployerFee0;
        uint256 fee1 = pairs[token0][token1].deployerFee1;

        pairs[token0][token1].deployerFee0 = 0;
        pairs[token0][token1].deployerFee1 = 0;

        tokenBalances[token0] -= fee0;
        tokenBalances[token1] -= fee1;

        TransferHelper.safeTransfer(token0, recipient, fee0);
        TransferHelper.safeTransfer(token1, recipient, fee1);

        emit DeployerFeeClaimed(token0, token1, fee0, fee1, recipient);
    }

    function _processSwapHop(address tokenA, address tokenB, uint256 amountIn) private returns (uint256 amountOut) {
        (address token0, address token1, bool zeroForOne) =
            tokenA < tokenB ? (tokenA, tokenB, true) : (tokenB, tokenA, false);

        Pair storage pair = pairs[token0][token1];
        uint256 poolId = pair.poolId;
        require(poolId > 0, pairNotFound()); // revert if 1. pool does not exist 2.token unsorted

        uint256 reserveInLong;
        uint256 reserveInShort;
        uint256 reserveOutLong;
        uint256 reserveOutShort;
        uint256 feeIn;

        if (zeroForOne) {
            (reserveInLong, reserveInShort, reserveOutLong, reserveOutShort) = getReserve(token0, token1);
            (feeIn,) = getFee(token0, token1);
        } else {
            (reserveOutLong, reserveOutShort, reserveInLong, reserveInShort) = getReserve(token0, token1);
            (, feeIn) = getFee(token0, token1);
        }

        // calculate fees
        uint256 totalFeeIn = (amountIn * feeIn) / 100000;
        uint256 protocolFee = totalFeeIn / 5;
        uint256 inputFee = (totalFeeIn - protocolFee) >> 1; // Half fee on input
        uint256 _amountIn = amountIn - inputFee;

        // k of long side does not grow
        uint256 reserveInLongAmount = (reserveInLong * _amountIn) / (reserveInLong + reserveInShort);
        uint256 kLong = reserveInLong * reserveOutLong;
        reserveInLong += reserveInLongAmount;
        uint256 newReserveOutLong = kLong / reserveInLong;
        amountOut = reserveOutLong - newReserveOutLong;
        reserveOutLong = newReserveOutLong;

        // k of short side grows
        reserveInShort += _amountIn - reserveInLongAmount + inputFee; // earn input fee
        uint256 newReserveOutShort = (reserveInShort * reserveOutLong) / reserveInLong; // use the ratio of long side to calculate short side
        amountOut += reserveOutShort - newReserveOutShort; // already include output fee(another half)
        reserveOutShort = newReserveOutShort;

        uint256 deployerFeeIn;
        if (!feeSwitch) {
            uint256 lpTokenId = zeroForOne ? poolId * 2 : (poolId * 2) - 1;
            uint256 totalLiquidity = totalSupply[lpTokenId];
            uint256 deployerLiquidity = balanceOf[pair.deployer][lpTokenId];
            deployerFeeIn = ((deployerLiquidity * protocolFee >> 1) / totalLiquidity);
            protocolFee -= deployerFeeIn;
        }

        if (zeroForOne) {
            _updatePair(
                token0,
                token1,
                reserveInLong,
                reserveInShort,
                reserveOutLong,
                reserveOutShort,
                deployerFeeIn,
                uint256(0)
            );

            tokenBalances[token0] += amountIn - protocolFee; // Receive input, deduct protocol fee
            tokenBalances[token1] -= amountOut; // Send output
        } else {
            _updatePair(
                token0,
                token1,
                reserveOutLong,
                reserveOutShort,
                reserveInLong,
                reserveInShort,
                uint256(0),
                deployerFeeIn
            );

            tokenBalances[token1] += amountIn - protocolFee; // Receive input, deduct protocol fee
            tokenBalances[token0] -= amountOut; // Send output
        }
    }
}
