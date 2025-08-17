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

    /// @notice The owner of the contract, with administrative privileges like setting new owner or sweeping excess tokens.
    address public override owner;

    /// @notice Mapping of pair IDs to their reserve and oracle data.
    mapping(uint256 => Pair) public override pairs;
    /// @notice Tracks the total reserved balance for each token across all pairs.
    mapping(address => uint256) public override tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }

    receive() external payable {}

    /// @notice Sets a new owner for the contract.
    /// @param _owner The address of the new owner.
    function setOwner(address _owner) external override {
        require(msg.sender == owner, forbidden());
        owner = _owner;
    }

    /// @notice Computes the unique ID for a token pair.
    /// @param token0 First token address (must be less than token1).
    /// @param token1 Second token address.
    /// @return pairId The computed pair ID.
    function getPairId(address token0, address token1) public pure override returns (uint256 pairId) {
        Validation.checkTokenOrder(token0, token1);
        pairId = PairLibrary.computePairId(token0, token1);
    }

    /// @notice Retrieves the long and short reserves for both tokens in a pair.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @return reserve0Long Long reserve of token0.
    /// @return reserve0Short Short reserve of token0.
    /// @return reserve1Long Long reserve of token1.
    /// @return reserve1Short Short reserve of token1.
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

    /// @notice Calculates the amount of a token that can be swept (excess beyond reserved balance).
    /// @param token The token address.
    /// @return The sweepable amount.
    function getSweepable(address token) public view override returns (uint256) {
        return PairLibrary.getBalance(token) - tokenBalances[token];
    }

    /// @notice Sweeps excess tokens to specified addresses (owner only).
    /// @param tokens Array of token addresses to sweep.
    /// @param amounts Array of amounts to sweep for each token.
    /// @param to Array of recipient addresses for each sweep.
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

    /// @notice Executes a flash loan, requiring repayment with fee in the callback.
    /// @param to Recipient of the loaned tokens.
    /// @param tokens Array of tokens to loan.
    /// @param amounts Array of amounts to loan for each token.
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

    /// @notice Creates or adds liquidity to a pair, minting LP tokens.
    /// @param to Recipient of the LP tokens.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param amount0Long Amount added to token0 long reserve.
    /// @param amount0Short Amount added to token0 short reserve.
    /// @param amount1Long Amount added to token1 long reserve.
    /// @param amount1Short Amount added to token1 short reserve.
    /// @return pairId The pair ID.
    /// @return liquidity0Long LP minted for token0 long.
    /// @return liquidity0Short LP minted for token0 short.
    /// @return liquidity1Long LP minted for token1 long.
    /// @return liquidity1Short LP minted for token1 short.
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

        // For new pairs, initialize minimal reserves and mint initial LP to address(0) for locking.
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

        // Calculate LP shares for each position type.
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

        // Update reserves and balances.
        _updatePair(pairId, reserve0Long, reserve0Short, reserve1Long, reserve1Short);
        _updateBalance(token0, token1, balance0, balance1);
        // Mint LP tokens.
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

    /// @notice Withdraws liquidity, burning LP tokens and applying exit fees.
    /// @param to Recipient of the withdrawn tokens.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param liquidity0Long LP to burn from token0 long.
    /// @param liquidity0Short LP to burn from token0 short.
    /// @param liquidity1Long LP to burn from token1 long.
    /// @param liquidity1Short LP to burn from token1 short.
    /// @return pairId The pair ID.
    /// @return amount0 Total token0 withdrawn.
    /// @return amount1 Total token1 withdrawn.
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

    /// @notice Performs a multi-hop swap along the given path.
    /// @param to Recipient of the output tokens.
    /// @param path Array of tokens defining the swap path.
    /// @param amount Input amount.
    /// @return amountOut Output amount received.
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

        // For each hop in the path:
        for (uint256 i; i < length - 1; i++) {
            // Determine direction and reserves.
            (address token0, address token1, bool zeroForOne) =
                path[i] < path[i + 1] ? (path[i], path[i + 1], true) : (path[i + 1], path[i], false);

            uint256 pairId = PairLibrary.computePairId(token0, token1);
            require(pairs[pairId].reserve0Long > 0, pairNotFound());

            (uint256 reserve0Long, uint256 reserve0Short, uint256 reserve1Long, uint256 reserve1Short) =
                getReserves(token0, token1);

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

    /// @dev Internal function to update pair reserves and cumulative oracle price.
    /// @param pairId The pair ID.
    /// @param reserve0Long Updated token0 long reserve.
    /// @param reserve0Short Updated token0 short reserve.
    /// @param reserve1Long Updated token1 long reserve.
    /// @param reserve1Short Updated token1 short reserve.
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
        // Update cumulative cube-root price for oracle.
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

    /// @dev Internal function to update token balances.
    /// @param token0 First token.
    /// @param token1 Second token.
    /// @param balance0 New balance for token0.
    /// @param balance1 New balance for token1.
    function _updateBalance(address token0, address token1, uint256 balance0, uint256 balance1) private {
        tokenBalances[token0] = balance0;
        tokenBalances[token1] = balance1;
    }
}
