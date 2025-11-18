// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IERC20} from "../interfaces/IERC20.sol";

library PairLibrary {
    uint256 internal constant MINIMUM_LIQUIDITY = 3000;
    uint256 internal constant SCALE = 340282366920938463463374607431768211456; // equal to 1<<128

    function getBalance(address token) internal view returns (uint256 balance) {
        balance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @dev Helper function to create token arrays for payment requests
    function createTokenArrays(address token0, address token1) internal pure returns (address[] memory tokens) {
        tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;
    }

    /// @dev Helper function to create amount arrays for payment requests
    function createAmountArrays(uint256 amount0, uint256 amount1) internal pure returns (uint256[] memory amounts) {
        amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;
    }
}
