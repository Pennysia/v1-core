// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {Liquidity} from "./abstracts/Liquidity.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {Validation} from "./libraries/Validation.sol";
import {PairLibrary} from "./libraries/PairLibrary.sol";

contract Market is IMarket, Liquidity {
    uint8 private constant FEE = 3; // 0.3%
    uint256 private constant SCALE = 340282366920938463463374607431768211456; // 2**128

    address public owner;

    mapping(uint256 => Pair) public pairs;
    mapping(address => uint256) public tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, forbidden());
        owner = _owner;
    }

    function getPairId(
        address token0,
        address token1
    ) public pure returns (uint256 pairId) {
        Validation.checkTokenOrder(token0, token1);
        pairId = PairLibrary.computePairId(token0, token1);
    }

    function getReserves(
        address token0,
        address token1
    )
        public
        view
        returns (
            uint128 reserve0Long,
            uint128 reserve0Short,
            uint128 reserve1Long,
            uint128 reserve1Short
        )
    {
        Validation.checkTokenOrder(token0, token1);
        uint256 pairId = PairLibrary.computePairId(token0, token1);
        reserve0Long = pairs[pairId].reserve0Long;
        reserve0Short = pairs[pairId].reserve0Short;
        reserve1Long = pairs[pairId].reserve1Long;
        reserve1Short = pairs[pairId].reserve1Short;
    }

    function getSweepable(address token) public view returns (uint256) {
        return PairLibrary.getBalance(token) - tokenBalances[token];
    }
}
