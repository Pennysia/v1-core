// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

abstract contract ReentrancyGuard {
    error Reentrancy();

    /// @dev Guards a function from reentrancy.
    /// Retreived from Soledge (https://github.com/vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol)
    modifier nonReentrant() virtual {
        assembly ("memory-safe") {
            /// @dev Equivalent to: `uint72(bytes9(keccak256("_REENTRANCY_GUARD_SLOT")))`.
            if tload(0x929eee149b4bd21268) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            tstore(0x929eee149b4bd21268, address())
        }
        _;
        assembly ("memory-safe") {
            tstore(0x929eee149b4bd21268, 0)
        }
    }
}
