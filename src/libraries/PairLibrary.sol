// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

import {IERC20} from "../interfaces/IERC20.sol";

library PairLibrary {
    function computePairId(
        address token0,
        address token1
    ) internal pure returns (uint256 pairId) {
        pairId = uint256(keccak256(abi.encodePacked(token0, token1)));
    }

    function getBalance(address token) internal view returns (uint256 balance) {
        balance = token == address(0)
            ? address(this).balance
            : IERC20(token).balanceOf(address(this));
    }
}
