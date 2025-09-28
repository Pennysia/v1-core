// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

abstract contract Deadline {
    error Expired();

    /// @dev Modifier to ensure an operation is performed before the deadline
    /// @param deadline The timestamp after which the operation is no longer valid
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, Expired());
        _;
    }
}
