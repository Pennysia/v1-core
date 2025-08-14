// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;
import {Liquidity} from "./abstracts/Liquidity.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {IMarket} from "./interfaces/IMarket.sol";

contract Market is IMarket, Liquidity {
    uint8 private constant FEE = 3; // 0.3%
    uint256 private constant SCALE = 340282366920938463463374607431768211456; // 2**128

    address public owner;

    mapping(uint256 => Pair) public pairs;
    mapping(address => uint256) public tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }
}
