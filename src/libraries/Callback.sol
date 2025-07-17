// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";
import {IPayment} from "../interfaces/IPayment.sol";
import {ILiquidity} from "../interfaces/ILiquidity.sol";

library Callback {
    error InsufficientPayback();

    function checkBal(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function tokenCallback(address caller, address to, address[] memory tokens, uint256[] memory expectedAmounts)
        internal
    {
        uint256 range = tokens.length;
        /// no need checking array length mismatch, it's done in Market.sol
        uint256[] memory amounts = new uint256[](range);
        // Record balances before
        for (uint256 i; i < range; i++) {
            amounts[i] = checkBal(tokens[i]);
        }

        IPayment(caller).requestToken(to, tokens, expectedAmounts); // user paybacks

        //verify payback amounts
        for (uint256 i; i < range; i++) {
            amounts[i] = checkBal(tokens[i]) - amounts[i];
            require(amounts[i] >= expectedAmounts[i], InsufficientPayback());
        }
    }

    function liquidityCallback(
        address caller,
        address to,
        uint256 poolId,
        uint128 amountLongX,
        uint128 amountShortX,
        uint128 amountLongY,
        uint128 amountShortY,
        ILiquidity.LpInfo memory lpInfoBefore
    ) internal {
        ILiquidity lpContract = ILiquidity(address(this));

        IPayment(caller).requestLiquidity(to, poolId, amountLongX, amountShortX, amountLongY, amountShortY); // user paybacks

        ILiquidity.LpInfo memory lpInfoAfter = lpContract.totalSupply(poolId);
        require(lpInfoAfter.longX <= lpInfoBefore.longX - amountLongX, InsufficientPayback());
        require(lpInfoAfter.shortX <= lpInfoBefore.shortX - amountShortX, InsufficientPayback());
        require(lpInfoAfter.longY <= lpInfoBefore.longY - amountLongY, InsufficientPayback());
        require(lpInfoAfter.shortY <= lpInfoBefore.shortY - amountShortY, InsufficientPayback());
    }
}
