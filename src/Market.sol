// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.30;

import {ERC6909} from "./abstracts/ERC6909.sol";
import {ReentrancyGuard} from "./abstracts/ReentrancyGuard.sol";
import {OwnerAction} from "./abstracts/OwnerAction.sol";

import {Callback} from "./libraries/Callback.sol";
import {Validation} from "./libraries/Validation.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Math} from "./libraries/Math.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {PairLibrary} from "./libraries/PairLibrary.sol";
import {Constant} from "./libraries/Constant.sol";

import {IMarket} from "./interfaces/IMarket.sol";

contract Market is IMarket, ERC6909, ReentrancyGuard, OwnerAction {
    using SafeCast for uint256;

    // token0 -> token1 -> pairId (required sorting of tokens)
    mapping(address => mapping(address => Pair)) public override pairs;

    uint256 public override totalPairs;

    constructor() OwnerAction(msg.sender) {}

    receive() external payable {}

    //--------------------------------- Read-Only Functions ---------------------------------

    function getPriceX128(address token0, address token1) public view override returns (uint256 priceX128) {
        Pair storage pair = pairs[token0][token1];
        priceX128 = Math.fullMulDiv(pair.reserve1, Constant.SCALE, pair.reserve0);
    }

    function getReserve(address token0, address token1)
        public
        view
        override
        returns (uint256 reserve0Long, uint256 reserve1)
    {
        reserve0Long = pairs[token0][token1].reserve0Long;
        reserve1Long = pairs[token0][token1].reserve1Long;
    }

    function getDirectionalReserve(address token0, address token1)
        public
        view
        override
        returns (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short)
    {
        Pair storage pair = pairs[token0][token1];
        uint256 reserve0 = pair.reserve0;
        uint256 reserve1 = pair.reserve1;

        reserve0Long = Math.fullMulDiv(reserve0, Constant.SCALE, pair.dividerX128);
        reserve0Short = reserve0 - reserve0Long;
        reserve1Long = Math.fullMulDiv(reserve1, Constant.SCALE, pair.dividerX128);
        reserve1Short = reserve1 - reserve1Long;
    }

    function getLiquidity(address token0, address token1)
        public
        view
        override
        returns (uint256 liquidity0, uint256 liquidity1)
    {
        uint256 idLong = pairs[token0][token1].idLong;
        uint256 idShort = pairs[token0][token1].idShort;
        liquidity0 = balanceOf[idLong];
        liquidity1 = balanceOf[idShort];
    }

    function getFee(address token0, address token1) public view override returns (uint256 fee0, uint256 fee1) {
        uint256 idLong = pairs[token0][token1].idLong;
        uint256 idShort = pairs[token0][token1].idShort;
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
        address callback = msg.sender;
        uint256 length = tokens.length;
        Validation.notThis(to);
        Validation.equalLengths(length, amounts.length);
        Validation.checkRedundantNative(tokens); // not allow duplicated native token in the array

        uint256[] memory paybackAmounts = new uint256[](length);
        uint256[] memory balancesBefore = new uint256[](length);

        for (uint256 i; i < length; i++) {
            paybackAmounts[i] = Math.fullMulDivUp(amounts[i], 1001, 1000); // fixed 0.1% fee (10 bps)
            TransferHelper.safeTransfer(tokens[i], to, amounts[i]);
            balancesBefore[i] = PairLibrary.getBalance(tokens[i]);
        }
        // user performs actions and payback in the callback.
        Callback.tokenCallback(callback, to, tokens, balancesBefore, paybackAmounts);
        emit Flash(callback, to, tokens, amounts, paybackAmounts);
    }

    /// NOTE: fee-on-transfer tokens are not supported.
    /// NOTE:  amount inputs by user may not be the same as the amount required by the contract
    // slippage tolerance is checked in the Router contract
    function deposit(
        address to, //DONE
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 dividerX128,
        uint256 fee // min = 100(0.1%), max = 500(0.5%)
    )
        external
        override
        nonReentrant
        onlyRouter
        returns (
            uint256 pairId,
            uint256 amount0Required,
            uint256 amount1Required,
            uint256 liquidityLong,
            uint256 liquidityShort
        )
    {
        Validation.notThis(to);
        Validation.checkFeeRange(fee);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens

        Pair storage pair = pairs[token0][token1];
        pairId = pair.pairId;

        uint256 reserve0Long;
        uint256 reserve0Short;
        uint256 reserve1Long;
        uint256 reserve1Short;

        // For new pairs, initialize minimal reserves and mint initial locked LP to address(0).
        if (pairId == 0) {
            pairId = totalPairs + 1;
            uint256 lpshortId = pairId * 2;
            uint256 lpLongId = lpshortId - 1;

            uint256 amount0Long = Math.fullMulDiv(amount0, dividerX128, Constant.SCALE);
            uint256 amount1Long = Math.fullMulDiv(amount1, dividerX128, Constant.SCALE);
            uint256 amount0Short = amount0 - amount0Long;
            uint256 amount1Short = amount1 - amount1Long;

            amount0Required = amount0;
            amount1Required = amount1;

            liquidityLong = Math.sqrt(amount0Long * amount1Long) - Constant.MINIMUM_LIQUIDITY;
            liquidityShort = Math.sqrt(amount0Short * amount1Short) - Constant.MINIMUM_LIQUIDITY;

            reserve0Long = amount0Long;
            reserve0Short = amount0Short;
            reserve1Long = amount1Long;
            reserve1Short = amount1Short;

            totalPairs = pairId;
            pair.pairId = pairId;
            pair.deployer = to;

            _mint(address(0), lpLongId, Constant.MINIMUM_LIQUIDITY);
            _mint(address(0), lpshortId, Constant.MINIMUM_LIQUIDITY);
        } else {}

        // update oracle and reserves
        _updateReserves(token0, token1, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

        // update balances
        tokenBalances[token0] += amount0Required;
        tokenBalances[token1] += amount1Required;

        // update vote
        voteFee(token0, token1, to, fee);

        //-- update Oracle, reserve,  feeWeight, and vote

        //1.create a pool if necessary
        //2.calculate the amounts required
        //3.update pairs, feeVote, totalPairs, mint LP tokens to user
        //4.call request payment from Router
        //5.emit Mint event

        // // Update reserves and balances.
        // _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        // _updateBalance(token0, token1, balance0, balance1);
        // // Mint LP tokens.
        // _mint(
        //     to,
        //     pairId,
        //     liquidity0Long.safe128(),
        //     liquidity0Short.safe128(),
        //     liquidity1Long.safe128(),
        //     liquidity1Short.safe128()
        // );
        // emit Mint(callback, to, pairId, totalAmount0, totalAmount1);
    }

    function withdraw(
        address to,
        address token0,
        address token1,
        uint256 liquidity0Long,
        uint256 liquidity0Short,
        uint256 liquidity1Long,
        uint256 liquidity1Short
    ) external override nonReentrant onlyRouter returns (uint256 pairId, uint256 amount0, uint256 amount1) {
        address callback = msg.sender;
        Validation.notThis(to);
        pairId = getPairId(token0, token1); //require pre-sorting of tokens
        require(pairs[pairId].reserve0Long > 0, pairNotFound());
        LpInfo memory lpInfo = _totalSupply[pairId];

        //request payment
        Callback.liquidityCallback(
            callback,
            to,
            pairId,
            liquidity0Long.safe128(),
            liquidity0Short.safe128(),
            liquidity1Long.safe128(),
            liquidity1Short.safe128(),
            lpInfo
        );

        uint256 reserve0Long = pairs[pairId].reserve0Long;
        uint256 reserve0Short = pairs[pairId].reserve0Short;
        uint256 reserve1Long = pairs[pairId].reserve1Long;
        uint256 reserve1Short = pairs[pairId].reserve1Short;

        uint256 fee0Long;
        uint256 fee0Short;
        uint256 fee1Long;
        uint256 fee1Short;

        uint256 amountOut;

        // Calculate exit fees and amounts out for each position.
        if (liquidity0Long > 0) {
            fee0Long = Math.divUp(liquidity0Long * FEE, 1000); // won't overflow because liquidity0Long is uint128
            amountOut = Math.fullMulDiv(liquidity0Long - fee0Long, reserve0Long, lpInfo.longX);
            amount0 += amountOut;
            reserve0Long -= amountOut;
            fee0Long = (fee0Long * 20) / 100;
        }
        if (liquidity0Short > 0) {
            fee0Short = Math.divUp(liquidity0Short * FEE, 1000); // won't overflow
            amountOut = Math.fullMulDiv(liquidity0Short - fee0Short, reserve0Short, lpInfo.shortX);
            amount0 += amountOut;
            reserve0Short -= amountOut;
            fee0Short = (fee0Short * 20) / 100;
        }
        if (liquidity1Long > 0) {
            fee1Long = Math.divUp(liquidity1Long * FEE, 1000); // won't overflow
            amountOut = Math.fullMulDiv(liquidity1Long - fee1Long, reserve1Long, lpInfo.longY);
            amount1 += amountOut;
            reserve1Long -= amountOut;
            fee1Long = (fee1Long * 20) / 100;
        }
        if (liquidity1Short > 0) {
            fee1Short = Math.divUp(liquidity1Short * FEE, 1000); // won't overflow
            amountOut = Math.fullMulDiv(liquidity1Short - fee1Short, reserve1Short, lpInfo.shortY);
            amount1 += amountOut;
            reserve1Short -= amountOut;
            fee1Short = (fee1Short * 20) / 100;
        }

        // Update reserves and balances.
        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        _updateBalance(token0, token1, tokenBalances[token0] - amount0, tokenBalances[token1] - amount1);

        // Mint protocol share of fees as LP.
        _mint(address(this), pairId, fee0Long.safe128(), fee0Short.safe128(), fee1Long.safe128(), fee1Short.safe128());

        // Transfer withdrawn tokens.
        TransferHelper.safeTransfer(token0, to, amount0);
        TransferHelper.safeTransfer(token1, to, amount1);
        emit Burn(callback, to, pairId, amount0, amount1);
    }

    function lpSwap(
        address to,
        address token0,
        address token1,
        bool longToShort0,
        uint256 liquidity0,
        bool longToShort1,
        uint256 liquidity1
    ) external override nonReentrant onlyRouter returns (uint256 pairId, uint256 liquidityOut0, uint256 liquidityOut1) {
        address callback = msg.sender;
        Validation.notThis(to);

        pairId = getPairId(token0, token1); //require pre-sorting of tokens
        (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short) = getReserves(pairId);
        require(reserve0Long > 0, pairNotFound());

        LpInfo memory lpInfo = _totalSupply[pairId];

        //acquire payment, burn LP tokens
        Callback.liquidityCallback(
            callback,
            to,
            pairId,
            longToShort0 ? liquidity0.safe128() : 0,
            longToShort0 ? 0 : liquidity0.safe128(),
            longToShort1 ? liquidity1.safe128() : 0,
            longToShort1 ? 0 : liquidity1.safe128(),
            lpInfo
        );

        uint128 toMint0Long;
        uint128 toMint0Short;
        uint128 toMint1Long;
        uint128 toMint1Short;

        if (liquidity0 > 0) {
            //get rate of long0 and short0
            uint256 rateLong0 = Math.fullMulDiv(lpInfo.longX, SCALE, reserve0Long);
            uint256 rateShort0 = Math.fullMulDiv(lpInfo.shortX, SCALE, reserve0Short);

            if (longToShort0) {
                liquidityOut0 = Math.fullMulDiv(liquidity0, rateShort0, rateLong0);

                uint256 reserveDeducted = Math.fullMulDiv(reserve0Long, liquidity0, lpInfo.longX);
                uint256 mintliquidity0 = Math.fullMulDiv(lpInfo.shortX, reserveDeducted, reserve0Short);

                reserve0Long -= reserveDeducted.safe128();
                require(reserve0Long > 0, minimumLiquidity());

                reserve0Short += reserveDeducted.safe128();
                toMint0Short = mintliquidity0.safe128();
            } else {
                liquidityOut0 = Math.fullMulDiv(liquidity0, rateLong0, rateShort0);

                uint256 reserveDeducted = Math.fullMulDiv(reserve0Short, liquidity0, lpInfo.shortX);
                uint256 mintliquidity0 = Math.fullMulDiv(lpInfo.longX, reserveDeducted, reserve0Long);

                reserve0Short -= reserveDeducted.safe128();
                require(reserve0Short > 0, minimumLiquidity());

                reserve0Long += reserveDeducted.safe128();
                toMint0Long = mintliquidity0.safe128();
            }
        }

        if (liquidity1 > 0) {
            //get rate of long1 and short1
            uint256 rateLong1 = Math.fullMulDiv(lpInfo.longY, SCALE, reserve1Long);
            uint256 rateShort1 = Math.fullMulDiv(lpInfo.shortY, SCALE, reserve1Short);

            if (longToShort1) {
                liquidityOut1 = Math.fullMulDiv(liquidity1, rateShort1, rateLong1);

                uint256 reserveDeducted = Math.fullMulDiv(reserve1Long, liquidity1, lpInfo.longY);
                uint256 mintliquidity1 = Math.fullMulDiv(lpInfo.shortY, reserveDeducted, reserve1Short);

                reserve1Long -= reserveDeducted.safe128();
                require(reserve1Long > 0, minimumLiquidity());

                reserve1Short += reserveDeducted.safe128();
                toMint1Short = mintliquidity1.safe128();
            } else {
                liquidityOut1 = Math.fullMulDiv(liquidity1, rateLong1, rateShort1);

                uint256 reserveDeducted = Math.fullMulDiv(reserve1Short, liquidity1, lpInfo.shortY);
                uint256 mintliquidity1 = Math.fullMulDiv(lpInfo.longY, reserveDeducted, reserve1Long);

                reserve1Short -= reserveDeducted.safe128();
                require(reserve1Short > 0, minimumLiquidity());

                reserve1Long += reserveDeducted.safe128();
                toMint1Long = mintliquidity1.safe128();
            }
        }

        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

        _mint(to, pairId, toMint0Long, toMint0Short, toMint1Long, toMint1Short);

        emit LiquiditySwap(
            callback, to, pairId, longToShort0, liquidity0, liquidityOut0, longToShort1, liquidity1, liquidityOut1
        );
    }

    function swap(address to, address[] memory path, uint256 amount)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint256 amountOut)
    {
        address callback = msg.sender;
        Validation.notThis(to);
        Validation.notZero(amount);
        uint256 length = path.length;
        require(length >= 2, invalidPath());

        uint256[] memory amountIn = new uint256[](1);
        amountIn[0] = amount;
        address[] memory tokenIn = new address[](1);
        tokenIn[0] = path[0];

        // For each hop in the path:
        for (uint256 i; i < length - 1; i++) {
            // Determine direction and reserves.
            (address token0, address token1, bool zeroForOne) =
                path[i] < path[i + 1] ? (path[i], path[i + 1], true) : (path[i + 1], path[i], false);

            uint256 pairId = getPairId(token0, token1); //require pre-sorting of tokens
            (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
                getReserves(pairId);

            require(reserve0Long > 0, pairNotFound());

            uint256 reserveIn = zeroForOne ? (reserve0Long + reserve0Short) : (reserve1Long + reserve1Short);
            uint256 reserveOut = zeroForOne ? (reserve1Long + reserve1Short) : (reserve0Long + reserve0Short);
            // Compute new reserves using constant product formula.
            uint256 newReserveIn = reserveIn + amount;
            uint256 newReserveOut = Math.fullMulDiv(reserveOut, reserveIn, newReserveIn);
            amountOut = reserveOut - newReserveOut;

            // Apply fees: adjust long/short splits.
            uint256 feeAmountOut = Math.divUp(amountOut * FEE, 1000); // won't overflow
            uint256 feeAmountIn = Math.divUp(amountIn[0] * FEE, 1000); // won't overflow

            if (zeroForOne) {
                // Scale output reserves and add fee to long.
                reserve1Long = Math.fullMulDiv(reserve1Long, newReserveOut, reserveOut);
                reserve1Short = newReserveOut - reserve1Long;
                reserve1Long += feeAmountOut; //100% fee goes to long positions of reserveOut

                // Scale input reserves and move fee from long to short.
                reserve0Long = Math.fullMulDiv(reserve0Long, newReserveIn, reserveIn);
                reserve0Short = newReserveIn - reserve0Long;
                if (reserve0Long > feeAmountIn) {
                    reserve0Long -= feeAmountIn;
                    reserve0Short += feeAmountIn;
                }
            } else {
                // Symmetric logic for the other direction.
                reserve0Long = Math.fullMulDiv(reserve0Long, newReserveOut, reserveOut);
                reserve0Short = newReserveOut - reserve0Long;
                reserve0Long += feeAmountOut; //100% fee goes to long positions of reserveOut

                reserve1Long = Math.fullMulDiv(reserve1Long, newReserveIn, reserveIn);
                reserve1Short = newReserveIn - reserve1Long;
                if (reserve1Long > feeAmountIn) {
                    reserve1Long -= feeAmountIn;
                    reserve1Short += feeAmountIn;
                }
            }
            amountOut -= feeAmountOut;
            amountIn[0] = amountOut; //chaining output as input for next swap

            _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

            (uint256 newBalance0, uint256 newBalance1) = zeroForOne
                ? (tokenBalances[token0] + amount, tokenBalances[token1] - amountOut)
                : (tokenBalances[token0] + amountOut, tokenBalances[token1] + amount);
            _updateBalance(token0, token1, newBalance0, newBalance1);
        }

        amountIn[0] = amount;
        uint256[] memory balancesBefore = new uint256[](1);
        balancesBefore[0] = PairLibrary.getBalance(path[0]);
        Callback.tokenCallback(callback, to, tokenIn, balancesBefore, amountIn); //user pays within this callback

        TransferHelper.safeTransfer(path[length - 1], to, amountOut); // transfer the output token to the user

        emit Swap(callback, to, path[0], path[length - 1], amount, amountOut);
    }

    function _updateReserves(
        address token0,
        address token1,
        uint256 reserve0Long,
        uint256 reserve0Short,
        uint256 reserve1Long,
        uint256 reserve1Short
    ) private {
        uint256 reserve0Total = reserve0Long + reserve0Short;
        uint256 reserve1Total = reserve1Long + reserve1Short;
        uint32 blockTimestamp = uint32(block.timestamp); // uint32 is enough for 136 years
        uint256 timeElapsed = blockTimestamp - pairs[pairId].blockTimestampLast;
        Pair storage pair = pairs[token0][token1];
        // Update cumulative cube-root price for oracle.
        if (timeElapsed > 0) {
            uint256 cbrtPriceX128 = Math.cbrt(Math.fullMulDiv(reserve1Total, Constant.SCALE, reserve0Total));
            pair.cbrtPriceX128CumulativeLast += (cbrtPriceX128 * timeElapsed); // (64bits * 32bits) won't overflow
            pair.blockTimestampLast = blockTimestamp;
        }

        require(reserve0Long > 0 && reserve0Short > 0 && reserve1Long > 0 && reserve1Short > 0, minimumLiquidity());
        pair.reserve0Long = reserve0Long.safe128();
        pair.reserve0Short = reserve0Short.safe128();
        pair.reserve1Long = reserve1Long.safe128();
        pair.reserve1Short = reserve1Short.safe128();
    }

    // function _updateBalance(address token0, address token1, uint256 balance0, uint256 balance1) private {
    //     tokenBalances[token0] = balance0;
    //     tokenBalances[token1] = balance1;
    // }
}
