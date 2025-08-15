// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {IPayment} from "../interfaces/IPayment.sol";
import {ILiquidity} from "../interfaces/ILiquidity.sol";
import {PairLibrary} from "./PairLibrary.sol";

library Callback {
    error InsufficientPayback();

    function tokenCallback(
        address caller,
        address to,
        address[] memory tokens,
        uint256[] memory balancesBefore,
        uint256[] memory paybackAmounts
    ) internal {
        uint256 len = tokens.length;
        IPayment(caller).requestToken(to, tokens, paybackAmounts); // user paybacks

        // Verify payback amounts for each token
        for (uint256 i = 0; i < len; i++) {
            uint256 paid = PairLibrary.getBalance(tokens[i]) -
                balancesBefore[i];
            require(paid >= paybackAmounts[i], InsufficientPayback());
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
        IPayment(caller).requestLiquidity(
            to,
            poolId,
            amountLongX,
            amountShortX,
            amountLongY,
            amountShortY
        ); // user paybacks

        (
            uint128 longXAfter,
            uint128 shortXAfter,
            uint128 longYAfter,
            uint128 shortYAfter
        ) = lpContract.totalSupply(poolId);

        require(
            longXAfter <= lpInfoBefore.longX - amountLongX,
            InsufficientPayback()
        );
        require(
            shortXAfter <= lpInfoBefore.shortX - amountShortX,
            InsufficientPayback()
        );
        require(
            longYAfter <= lpInfoBefore.longY - amountLongY,
            InsufficientPayback()
        );
        require(
            shortYAfter <= lpInfoBefore.shortY - amountShortY,
            InsufficientPayback()
        );
    }
}
