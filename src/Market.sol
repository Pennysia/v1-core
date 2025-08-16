// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {Liquidity} from "./abstracts/Liquidity.sol";
import {NoDelegatecall} from "./abstracts/NoDelegatecall.sol";
import {ReentrancyGuard} from "./abstracts/ReentrancyGuard.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {Callback} from "./libraries/Callback.sol";
import {Validation} from "./libraries/Validation.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {Math} from "./libraries/Math.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {PairLibrary} from "./libraries/PairLibrary.sol";

contract Market is IMarket, Liquidity, NoDelegatecall, ReentrancyGuard {
    using SafeCast for uint256;

    uint8 private constant FEE = 3; // 0.3%
    uint256 private constant SCALE = 340282366920938463463374607431768211456; // 2**128

    address public override owner;

    mapping(uint256 => Pair) public override pairs;
    mapping(address => uint256) public override tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }

    receive() external payable {}

    function setOwner(address _owner) external override {
        require(msg.sender == owner, forbidden());
        owner = _owner;
    }

    function getPairId(address token0, address token1) public pure override returns (uint256 pairId) {
        Validation.checkTokenOrder(token0, token1);
        pairId = PairLibrary.computePairId(token0, token1);
    }

    function getReserves(address token0, address token1)
        public
        view
        override
        returns (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short)
    {
        Validation.checkTokenOrder(token0, token1);

        uint256 pairId = PairLibrary.computePairId(token0, token1);
        reserve0Long = pairs[pairId].reserve0Long;
        reserve0Short = pairs[pairId].reserve0Short;
        reserve1Long = pairs[pairId].reserve1Long;
        reserve1Short = pairs[pairId].reserve1Short;
    }

    function getSweepable(address token) public view override returns (uint256) {
        return PairLibrary.getBalance(token) - tokenBalances[token];
    }

    function sweep(address[] calldata tokens, uint256[] calldata amounts, address[] calldata to)
        external
        override
        nonReentrant
        noDelegateCall
    {
        require(msg.sender == owner, forbidden());
        uint256 length = tokens.length;
        Validation.equalLengths(length, amounts.length);
        Validation.equalLengths(length, to.length);
        for (uint256 i; i < length; i++) {
            require(amounts[i] <= getSweepable(tokens[i]), excessiveSweep());
            TransferHelper.safeTransfer(tokens[i], to[i], amounts[i]);
        }
        emit Sweep(msg.sender, to, tokens, amounts);
    }

    function flash(address to, address[] calldata tokens, uint256[] calldata amounts)
        external
        override
        nonReentrant
        noDelegateCall
    {
        address callback = msg.sender;
        uint256 length = tokens.length;
        Validation.notThis(to);
        Validation.equalLengths(length, amounts.length);
        Validation.checkUnique(tokens);

        uint256[] memory paybackAmounts = new uint256[](length);
        uint256[] memory balancesBefore = new uint256[](length);

        for (uint256 i; i < length; i++) {
            paybackAmounts[i] = Math.fullMulDivUp(amounts[i], 1003, 1000); // include 0.3% fee (30 bps)
            TransferHelper.safeTransfer(tokens[i], to, amounts[i]);
            balancesBefore[i] = PairLibrary.getBalance(tokens[i]);
        }
        // user performs actions and payback in the callback.
        Callback.tokenCallback(callback, to, tokens, balancesBefore, paybackAmounts);
        emit Flash(callback, to, tokens, amounts, paybackAmounts);
    }

    // this low-level function should be called from a contract which performs important safety checks
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
        nonReentrant
        noDelegateCall
        returns (
            uint256 pairId,
            uint256 liquidity0Long,
            uint256 liquidity0Short,
            uint256 liquidity1Long,
            uint256 liquidity1Short
        )
    {
        address callback = msg.sender;
        Validation.notThis(to);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens
        pairId = PairLibrary.computePairId(token0, token1);
        //request payment
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0Long + amount0Short;
        amounts[1] = amount1Long + amount1Short;
        uint256[] memory balancesBefore = new uint256[](2);
        balancesBefore[0] = PairLibrary.getBalance(token0);
        balancesBefore[1] = PairLibrary.getBalance(token1);

        Callback.tokenCallback(callback, to, tokens, balancesBefore, amounts); //user pays within this callback

        uint256 reserve0Long;
        uint256 reserve0Short;
        uint256 reserve1Long;
        uint256 reserve1Short;

        uint256 balance0 = tokenBalances[token0];
        uint256 balance1 = tokenBalances[token1];

        if (pairs[pairId].reserve0Long == 0) {
            reserve0Long = 1000;
            reserve0Short = 1000;
            reserve1Long = 1000;
            reserve1Short = 1000;
            uint128 million = 1000000;
            _mint(address(0), pairId, million, million, million, million); // intial ratio 1:1000
            emit Mint(callback, address(0), pairId, 1000000, 1000000);

            balance0 += 2000;
            balance1 += 2000;
            require(
                amount0Long >= reserve0Long && amount0Short >= reserve0Short && amount1Long >= reserve1Long
                    && amount1Short >= reserve1Short,
                minimumLiquidity()
            );
            amount0Long -= reserve0Long;
            amount0Short -= reserve0Short;
            amount1Long -= reserve1Long;
            amount1Short -= reserve1Short;
            emit Create(token0, token1, pairId);
        } else {
            reserve0Long = pairs[pairId].reserve0Long;
            reserve0Short = pairs[pairId].reserve0Short;
            reserve1Long = pairs[pairId].reserve1Long;
            reserve1Short = pairs[pairId].reserve1Short;
        }

        LpInfo storage lpInfo = _totalSupply[pairId];

        if (amount0Long > 0) {
            liquidity0Long = Math.fullMulDiv(amount0Long, lpInfo.longX, reserve0Long);
            reserve0Long += amount0Long;
        }
        if (amount0Short > 0) {
            liquidity0Short = Math.fullMulDiv(amount0Short, lpInfo.shortX, reserve0Short);
            reserve0Short += amount0Short;
        }
        if (amount1Long > 0) {
            liquidity1Long = Math.fullMulDiv(amount1Long, lpInfo.longY, reserve1Long);
            reserve1Long += amount1Long;
        }
        if (amount1Short > 0) {
            liquidity1Short = Math.fullMulDiv(amount1Short, lpInfo.shortY, reserve1Short);
            reserve1Short += amount1Short;
        }

        uint256 totalAmount0 = amount0Long + amount0Short;
        uint256 totalAmount1 = amount1Long + amount1Short;
        balance0 += totalAmount0;
        balance1 += totalAmount1;

        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        _updateBalance(token0, token1, balance0, balance1);
        _mint(
            to,
            pairId,
            liquidity0Long.safe128(),
            liquidity0Short.safe128(),
            liquidity1Long.safe128(),
            liquidity1Short.safe128()
        );
        emit Mint(callback, to, pairId, totalAmount0, totalAmount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function withdrawLiquidity(
        address to,
        address token0,
        address token1,
        uint256 liquidity0Long,
        uint256 liquidity0Short,
        uint256 liquidity1Long,
        uint256 liquidity1Short
    ) external nonReentrant noDelegateCall returns (uint256 pairId, uint256 amount0, uint256 amount1) {
        address callback = msg.sender;
        Validation.notThis(to);
        Validation.checkTokenOrder(token0, token1);
        pairId = PairLibrary.computePairId(token0, token1);
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

        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        _updateBalance(token0, token1, tokenBalances[token0] - amount0, tokenBalances[token1] - amount1);

        // mint 20% of fees to the protocol as reserve and protocol fees
        _mint(address(this), pairId, fee0Long.safe128(), fee0Short.safe128(), fee1Long.safe128(), fee1Short.safe128());

        TransferHelper.safeTransfer(token0, to, amount0);
        TransferHelper.safeTransfer(token1, to, amount1);
        emit Burn(callback, to, pairId, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(address to, address[] memory path, uint256 amount)
        external
        nonReentrant
        noDelegateCall
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

        for (uint256 i; i < length - 1; i++) {
            (address token0, address token1, bool zeroForOne) =
                path[i] < path[i + 1] ? (path[i], path[i + 1], true) : (path[i + 1], path[i], false);

            uint256 pairId = PairLibrary.computePairId(token0, token1);
            require(pairs[pairId].reserve0Long > 0, pairNotFound());

            (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
                getReserves(token0, token1);

            uint256 reserveIn = zeroForOne ? (reserve0Long + reserve0Short) : (reserve1Long + reserve1Short);
            uint256 reserveOut = zeroForOne ? (reserve1Long + reserve1Short) : (reserve0Long + reserve0Short);
            uint256 newReserveIn = reserveIn + amount;
            uint256 newReserveOut = Math.fullMulDiv(reserveOut, reserveIn, newReserveIn);
            amountOut = reserveOut - newReserveOut;

            uint256 feeAmountOut = Math.divUp(amountOut * FEE, 1000); // won't overflow
            uint256 feeAmountIn = Math.divUp(amountIn[0] * FEE, 1000); // won't overflow

            if (zeroForOne) {
                reserve1Long = Math.fullMulDiv(reserve1Long, newReserveOut, reserveOut);
                reserve1Short = newReserveOut - reserve1Long;
                reserve1Long += feeAmountOut; //100% fee goes to long positions of reserveOut

                reserve0Long = Math.fullMulDiv(reserve0Long, newReserveIn, reserveIn);
                reserve0Short = newReserveIn - reserve0Long;
                if (reserve0Long > feeAmountIn) {
                    reserve0Long -= feeAmountIn;
                    reserve0Short += feeAmountIn;
                }
            } else {
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

    function _updatePair(
        uint256 pairId,
        uint256 reserve0Long,
        uint256 reserve0Short,
        uint256 reserve1Long,
        uint256 reserve1Short
    ) private {
        uint256 reserve0Total = reserve0Long + reserve0Short;
        uint256 reserve1Total = reserve1Long + reserve1Short;
        uint64 blockTimestamp = uint64(block.timestamp); // won't overflow until the year 292 billion AD.
        uint64 timeElasped = blockTimestamp - pairs[pairId].blockTimestampLast;
        if (timeElasped > 0) {
            uint256 priceX128 = Math.fullMulDiv(reserve1Total, SCALE, reserve0Total);
            uint256 cbrtPriceX128 = Math.cbrt(priceX128);
            pairs[pairId].cbrtPriceX128CumulativeLast += uint192(cbrtPriceX128 * timeElasped); // won't overflow
        }
        pairs[pairId].blockTimestampLast = blockTimestamp;

        require(reserve0Long > 0 && reserve0Short > 0 && reserve1Long > 0 && reserve1Short > 0, minimumLiquidity());
        pairs[pairId].reserve0Long = reserve0Long.safe128();
        pairs[pairId].reserve0Short = reserve0Short.safe128();
        pairs[pairId].reserve1Long = reserve1Long.safe128();
        pairs[pairId].reserve1Short = reserve1Short.safe128();
    }

    function _updateBalance(address token0, address token1, uint256 balance0, uint256 balance1) private {
        tokenBalances[token0] = balance0;
        tokenBalances[token1] = balance1;
    }
}
