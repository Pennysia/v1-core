// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

library Validation {
    error orderError();
    error lengthError();
    error selfCall();
    error zeroValue();
    error duplicatedInput();

    function checkTokenOrder(address input0, address input1) internal pure {
        require(input0 < input1, orderError());
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

    function checkRedundantNative(address[] memory inputs) internal pure {
        bool hasNative;
        for (uint256 i = 0; i < inputs.length; i++) {
            if (inputs[i] == address(0)) {
                require(!hasNative, duplicatedInput());
                hasNative = true;
            }
        }
    }
}
