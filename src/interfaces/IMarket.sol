// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

interface IMarket {
    struct Pair {
        uint128 reserve0Long;
        uint128 reserve0Short;
        uint128 reserve1Long;
        uint128 reserve1Short;
        uint64 blockTimestampLast;
        uint192 cbrtPriceX128CumulativeLast; // cum. of cbrt(y/x * 10^128)*timeElapsed
    }
}
