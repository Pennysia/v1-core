// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IERC20} from "../interfaces/IERC20.sol";

library PairLibrary {
    function getBalance(address token) internal view returns (uint256 balance) {
        balance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }
}
