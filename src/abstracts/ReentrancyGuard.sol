// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

abstract contract ReentrancyGuard {
    error Reentrancy();

    /// @dev Equivalent to: `uint72(bytes9(keccak256("_REENTRANCY_GUARD_SLOT")))`.
    /// 9 bytes is large enough to avoid collisions in practice,
    /// but not too large to result in excessive bytecode bloat.
    uint256 private constant _REENTRANCY_GUARD_SLOT = 0x929eee149b4bd21268;

    /// @dev Guards a function from reentrancy.
    /// Retreived from Soledge (https://github.com/vectorized/soledge/blob/main/src/utils/ReentrancyGuard.sol)
    modifier nonReentrant() virtual {
        /// @solidity memory-safe-assembly
        assembly {
            if tload(_REENTRANCY_GUARD_SLOT) {
                mstore(0x00, 0xab143c06) // `Reentrancy()`.
                revert(0x1c, 0x04)
            }
            tstore(_REENTRANCY_GUARD_SLOT, address())
        }
        _;
        /// @solidity memory-safe-assembly
        assembly {
            tstore(_REENTRANCY_GUARD_SLOT, 0)
        }
    }
}
