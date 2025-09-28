// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Validation {
    error tokenError();
    error lengthError();
    error selfCall();
    error zeroValue();
    error duplicatedToken();

    function checkTokenOrder(address token0, address token1) internal pure {
        require(token0 < token1, tokenError());
    }

    function equalLengths(uint256 length0, uint256 length1) internal pure {
        require(length0 == length1, lengthError());
    }

    function notThis(address input) internal view {
        require(input != address(this), selfCall());
    }

    function notZero(uint256 input) internal pure {
        require(input > 0, zeroValue());
    }

    function checkUnique(address[] memory tokens) internal pure {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = i + 1; j < tokens.length; j++) {
                require(tokens[i] != tokens[j], duplicatedToken());
            }
        }
    }
}
