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

    uint256 public override totalPairs;

    constructor() OwnerAction(msg.sender) {}

    receive() external payable {}

    //--------------------------------- Read-Only Functions ---------------------------------

    function getPrice(address token0, address token1) public view override returns (uint256 price) {
        Pair storage pair = pairs[token0][token1];
        price = Math.fullMulDiv(pair.reserve1, Validation.SCALE, pair.reserve0);
    }

    function getReserve(address token0, address token1)
        public
        view
        override
        returns (uint256 reserve0, uint256 reserve1)
    {
        reserve0 = pairs[token0][token1].reserve0;
        reserve1 = pairs[token0][token1].reserve1;
    }

    function getDirectionalReserve(address token0, address token1)
        public
        view
        override
        returns (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short)
    {
        uint256 reserve0 = pairs[token0][token1].reserve0;
        uint256 reserve1 = pairs[token0][token1].reserve1;
        uint256 _divider = pairs[token0][token1].divider;

        reserve0Long = Math.fullMulDiv(reserve0, Validation.SCALE, _divider);
        reserve0Short = reserve0 - reserve0Long;
        reserve1Long = Math.fullMulDiv(reserve1, Validation.SCALE, _divider);
        reserve1Short = reserve1 - reserve1Long;
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

    /// NOTE: fee-on-transfer tokens are NOT supported.
    /// NOTE: all amount0 and amount1 inputs here are permanently locked liquidity.
    function create(address deployer, address token0, address token1, uint256 amount0, uint256 amount1, uint256 fee)
        external
        override
        nonReentrant
        onlyRouter
        returns (uint256 poolId)
    {
        Validation.notThis(deployer);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens
        fee = Validation.checkFeeRange(fee); // modify fee to the range [100, 500]

        Pair storage pair = pairs[token0][token1];
        require(pair.poolId == 0, pairAlreadyExists());
        poolId = totalPairs + 1;
        uint256 idShort = poolId * 2;
        uint256 idLong = idShort - 1;
        uint256 halfLiquidity = Math.sqrt(amount0 * amount1) >> 1;
        require(halfLiquidity > Validation.MINIMUM_LIQUIDITY, notEnoughLiquidity());

        //--- Step 1: ask for payment
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
        IPayment(msg.sender).requestToken(deployer, tokens, amounts); // user paybacks

        //--- Step2: mint liquidity and update reserve
        _mint(address(0), idLong, halfLiquidity, fee); // locked liquidity
        _mint(address(0), idShort, halfLiquidity, fee); // locked liquidity

        totalPairs = poolId;
        pair.poolId = poolId.safe128();
        pair.deployer = deployer;

        _updateReserve(token0, token1, amount0, amount1, Validation.SCALE >> 1);

        tokenBalances[token0] += amount0;
        tokenBalances[token1] += amount1;
        emit Create(token0, token1, deployer);
    }

    // NOTE: fee-on-transfer tokens are NOT supported.
    // NOTE: slippage tolerance is checked in the Router contract.
    // NOTE: if amount0 or amount1 is 0, liquidity output will become 0.
    function deposit(
        address to, //checked
        address token0, //checked
        address token1, //checked
        uint256 liquidityLong,
        uint256 liquidityShort,
        uint256 fee //checked
    ) external override nonReentrant onlyRouter returns (uint256 amount0Required, uint256 amount1Required) {
        Validation.notThis(to);
        Validation.checkTokenOrder(token0, token1); // require pre-sorting of tokens
        fee = Validation.checkFeeRange(fee); // modify fee to the range [100, 500]

        uint256 poolId = pairs[token0][token1].poolId;
        require(poolId > 0, pairNotFound());

        //1.calculate how much amount0Long, 0short, 1long, 1short
        (uint256 supplyLong, uint256 supplyShort) = getLiquidity(token0, token1);
        (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
            getDirectionalReserve(token0, token1);

        uint256 amount0Long = Math.fullMulDiv(liquidityLong, reserve0Long, supplyLong);
        uint256 amount0Short = Math.fullMulDiv(liquidityShort, reserve0Short, supplyShort);
        uint256 amount1Long = Math.fullMulDiv(liquidityLong, reserve1Long, supplyLong);
        uint256 amount1Short = Math.fullMulDiv(liquidityShort, reserve1Short, supplyShort);

        //2.calculate amount0Required, amount1Required
        amount0Required = amount0Long + amount0Short;
        amount1Required = amount1Long + amount1Short;

        uint256 reserve0 = reserve0Long + reserve0Short + amount0Required;
        uint256 reserve1 = reserve1Long + reserve1Short + amount1Required;

        //3.calculate new divider
        uint256 divider0 = Math.fullMulDiv(reserve0, Validation.SCALE, reserve0Long + amount0Long);
        uint256 divider1 = Math.fullMulDiv(reserve1, Validation.SCALE, reserve1Long + amount1Long);
        uint256 _divider = PairLibrary.max(divider0, divider1); // only use the most precised one

        //4.ask for payment
        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0Required;
        amounts[1] = amount1Required;
        IPayment(msg.sender).requestToken(to, tokens, amounts); // ask Router to pay

        //5.mint liquidity
        _mint(to, (poolId * 2) - 1, liquidityLong, fee);
        _mint(to, poolId * 2, liquidityShort, fee);

        //6.update reserve
        _updateReserve(token0, token1, reserve0, reserve1, _divider);
        tokenBalances[token0] += amount0Required;
        tokenBalances[token1] += amount1Required;

        // 4.emit Mint event
        emit Mint(to, token0, token1, amount0Required, amount1Required, liquidityLong, liquidityShort);
    }

    // function withdraw(
    //     address to,
    //     address token0,
    //     address token1,
    //     uint256 liquidity0Long,
    //     uint256 liquidity0Short,
    //     uint256 liquidity1Long,
    //     uint256 liquidity1Short
    // ) external override nonReentrant onlyRouter returns (uint256 pairId, uint256 amount0, uint256 amount1) {
    //     address callback = msg.sender;
    //     Validation.notThis(to);
    //     pairId = getPairId(token0, token1); //require pre-sorting of tokens
    //     require(pairs[pairId].reserve0Long > 0, pairNotFound());
    //     LpInfo memory lpInfo = _totalSupply[pairId];

    //     //request payment
    //     Callback.liquidityCallback(
    //         callback,
    //         to,
    //         pairId,
    //         liquidity0Long.safe128(),
    //         liquidity0Short.safe128(),
    //         liquidity1Long.safe128(),
    //         liquidity1Short.safe128(),
    //         lpInfo
    //     );

    //     uint256 reserve0Long = pairs[pairId].reserve0Long;
    //     uint256 reserve0Short = pairs[pairId].reserve0Short;
    //     uint256 reserve1Long = pairs[pairId].reserve1Long;
    //     uint256 reserve1Short = pairs[pairId].reserve1Short;

    //     uint256 fee0Long;
    //     uint256 fee0Short;
    //     uint256 fee1Long;
    //     uint256 fee1Short;

    //     uint256 amountOut;

    //     // Calculate exit fees and amounts out for each position.
    //     if (liquidity0Long > 0) {
    //         fee0Long = Math.divUp(liquidity0Long * FEE, 1000); // won't overflow because liquidity0Long is uint128
    //         amountOut = Math.fullMulDiv(liquidity0Long - fee0Long, reserve0Long, lpInfo.longX);
    //         amount0 += amountOut;
    //         reserve0Long -= amountOut;
    //         fee0Long = (fee0Long * 20) / 100;
    //     }
    //     if (liquidity0Short > 0) {
    //         fee0Short = Math.divUp(liquidity0Short * FEE, 1000); // won't overflow
    //         amountOut = Math.fullMulDiv(liquidity0Short - fee0Short, reserve0Short, lpInfo.shortX);
    //         amount0 += amountOut;
    //         reserve0Short -= amountOut;
    //         fee0Short = (fee0Short * 20) / 100;
    //     }
    //     if (liquidity1Long > 0) {
    //         fee1Long = Math.divUp(liquidity1Long * FEE, 1000); // won't overflow
    //         amountOut = Math.fullMulDiv(liquidity1Long - fee1Long, reserve1Long, lpInfo.longY);
    //         amount1 += amountOut;
    //         reserve1Long -= amountOut;
    //         fee1Long = (fee1Long * 20) / 100;
    //     }
    //     if (liquidity1Short > 0) {
    //         fee1Short = Math.divUp(liquidity1Short * FEE, 1000); // won't overflow
    //         amountOut = Math.fullMulDiv(liquidity1Short - fee1Short, reserve1Short, lpInfo.shortY);
    //         amount1 += amountOut;
    //         reserve1Short -= amountOut;
    //         fee1Short = (fee1Short * 20) / 100;
    //     }

    //     // Update reserves and balances.
    //     _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
    //     _updateBalance(token0, token1, tokenBalances[token0] - amount0, tokenBalances[token1] - amount1);

    //     // Mint protocol share of fees as LP.
    //     _mint(address(this), pairId, fee0Long.safe128(), fee0Short.safe128(), fee1Long.safe128(), fee1Short.safe128());

    //     // Transfer withdrawn tokens.
    //     TransferHelper.safeTransfer(token0, to, amount0);
    //     TransferHelper.safeTransfer(token1, to, amount1);
    //     emit Burn(callback, to, pairId, amount0, amount1);
    // }

    // function lpSwap(
    //     address to,
    //     address token0,
    //     address token1,
    //     bool longToShort0,
    //     uint256 liquidity0,
    //     bool longToShort1,
    //     uint256 liquidity1
    // ) external override nonReentrant onlyRouter returns (uint256 pairId, uint256 liquidityOut0, uint256 liquidityOut1) {
    //     address callback = msg.sender;
    //     Validation.notThis(to);

    //     pairId = getPairId(token0, token1); //require pre-sorting of tokens
    //     (uint128 reserve0Long, uint128 reserve0Short, uint128 reserve1Long, uint128 reserve1Short) = getReserves(pairId);
    //     require(reserve0Long > 0, pairNotFound());

    //     LpInfo memory lpInfo = _totalSupply[pairId];

    //     //acquire payment, burn LP tokens
    //     Callback.liquidityCallback(
    //         callback,
    //         to,
    //         pairId,
    //         longToShort0 ? liquidity0.safe128() : 0,
    //         longToShort0 ? 0 : liquidity0.safe128(),
    //         longToShort1 ? liquidity1.safe128() : 0,
    //         longToShort1 ? 0 : liquidity1.safe128(),
    //         lpInfo
    //     );

    //     uint128 toMint0Long;
    //     uint128 toMint0Short;
    //     uint128 toMint1Long;
    //     uint128 toMint1Short;

    //     if (liquidity0 > 0) {
    //         //get rate of long0 and short0
    //         uint256 rateLong0 = Math.fullMulDiv(lpInfo.longX, SCALE, reserve0Long);
    //         uint256 rateShort0 = Math.fullMulDiv(lpInfo.shortX, SCALE, reserve0Short);

    //         if (longToShort0) {
    //             liquidityOut0 = Math.fullMulDiv(liquidity0, rateShort0, rateLong0);

    //             uint256 reserveDeducted = Math.fullMulDiv(reserve0Long, liquidity0, lpInfo.longX);
    //             uint256 mintliquidity0 = Math.fullMulDiv(lpInfo.shortX, reserveDeducted, reserve0Short);

    //             reserve0Long -= reserveDeducted.safe128();
    //             require(reserve0Long > 0, minimumLiquidity());

    //             reserve0Short += reserveDeducted.safe128();
    //             toMint0Short = mintliquidity0.safe128();
    //         } else {
    //             liquidityOut0 = Math.fullMulDiv(liquidity0, rateLong0, rateShort0);

    //             uint256 reserveDeducted = Math.fullMulDiv(reserve0Short, liquidity0, lpInfo.shortX);
    //             uint256 mintliquidity0 = Math.fullMulDiv(lpInfo.longX, reserveDeducted, reserve0Long);

    //             reserve0Short -= reserveDeducted.safe128();
    //             require(reserve0Short > 0, minimumLiquidity());

    //             reserve0Long += reserveDeducted.safe128();
    //             toMint0Long = mintliquidity0.safe128();
    //         }
    //     }

    //     if (liquidity1 > 0) {
    //         //get rate of long1 and short1
    //         uint256 rateLong1 = Math.fullMulDiv(lpInfo.longY, SCALE, reserve1Long);
    //         uint256 rateShort1 = Math.fullMulDiv(lpInfo.shortY, SCALE, reserve1Short);

    //         if (longToShort1) {
    //             liquidityOut1 = Math.fullMulDiv(liquidity1, rateShort1, rateLong1);

    //             uint256 reserveDeducted = Math.fullMulDiv(reserve1Long, liquidity1, lpInfo.longY);
    //             uint256 mintliquidity1 = Math.fullMulDiv(lpInfo.shortY, reserveDeducted, reserve1Short);

    //             reserve1Long -= reserveDeducted.safe128();
    //             require(reserve1Long > 0, minimumLiquidity());

    //             reserve1Short += reserveDeducted.safe128();
    //             toMint1Short = mintliquidity1.safe128();
    //         } else {
    //             liquidityOut1 = Math.fullMulDiv(liquidity1, rateLong1, rateShort1);

    //             uint256 reserveDeducted = Math.fullMulDiv(reserve1Short, liquidity1, lpInfo.shortY);
    //             uint256 mintliquidity1 = Math.fullMulDiv(lpInfo.longY, reserveDeducted, reserve1Long);

    //             reserve1Short -= reserveDeducted.safe128();
    //             require(reserve1Short > 0, minimumLiquidity());

    //             reserve1Long += reserveDeducted.safe128();
    //             toMint1Long = mintliquidity1.safe128();
    //         }
    //     }

    //     _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);

    //     _mint(to, pairId, toMint0Long, toMint0Short, toMint1Long, toMint1Short);

    //     emit LiquiditySwap(
    //         callback, to, pairId, longToShort0, liquidity0, liquidityOut0, longToShort1, liquidity1, liquidityOut1
    //     );
    // }

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

    function _updateReserve(address token0, address token1, uint256 reserve0, uint256 reserve1, uint256 dividerX128)
        private
    {
        Pair storage pair = pairs[token0][token1];
        uint96 blockTimestamp = uint96(block.timestamp); // uint32 is enough for 136 years
        uint256 timeElapsed = blockTimestamp - pair.blockTimestampLast;
        if (timeElapsed > 0) {
            uint256 cbrtPrice = Math.cbrt(Math.fullMulDiv(reserve1, Validation.SCALE, reserve0));
            pair.cbrtPriceCumulativeLast += (cbrtPrice * timeElapsed);
            pair.blockTimestampLast = blockTimestamp;
        }
        pair.reserve0 = reserve0.safe128();
        pair.reserve1 = reserve1.safe128();
        pair.divider = dividerX128.safe128();
    }
}
