// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library SafeCast {
    error SafeCastOverflow();

    function safe128(uint256 x) internal pure returns (uint128 y) {
        y = uint128(x);
        require(y == x, SafeCastOverflow());
    }

    function safe64(uint256 x) internal pure returns (uint64 y) {
        y = uint64(x);
        require(y == x, SafeCastOverflow());
    }
}
