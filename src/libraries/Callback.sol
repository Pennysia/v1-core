// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IPayment} from "../interfaces/IPayment.sol";
import {PairLibrary} from "./PairLibrary.sol";

library Callback {
    error InsufficientPayback();

    function tokenCallback(
        address caller,
        address payer,
        address[] memory tokens,
        uint256[] memory balancesBefore,
        uint256[] memory paybackAmounts
    ) internal {
        uint256 len = tokens.length;
        IPayment(caller).requestToken(payer, tokens, paybackAmounts); // user paybacks

        // Verify payback amounts for each token
        for (uint256 i = 0; i < len; i++) {
            uint256 paid = PairLibrary.getBalance(tokens[i]) - balancesBefore[i];
            require(paid >= paybackAmounts[i], InsufficientPayback());
        }
    }
}
