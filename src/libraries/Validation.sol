// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

library Validation {
    error tokenError();
    error selfCall();

    function checkTokenOrder(address token0, address token1) internal pure {
        require(token0 < token1, tokenError());
    }

    function notThis(address input) internal view {
        require(input != address(this), selfCall());
    }
}
