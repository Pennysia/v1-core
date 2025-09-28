// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

abstract contract NoDelegatecall {
    error DelegateCallNotAllowed();

    /// @dev The original address of this contract
    address private immutable original;

    constructor() {
        // Immutables are computed in the init code of the contract, and then inlined into the deployed bytecode.
        // In other words, this variable won't change when it's checked at runtime.
        original = address(this);
    }

    /// @dev Prevents delegatecall into the modified method
    modifier noDelegateCall() {
        require(address(this) == original, DelegateCallNotAllowed());
        _;
    }
}
