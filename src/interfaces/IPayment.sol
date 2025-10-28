// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

/// @title IPayment
///@notice these are payment request callbacks covering mint, burn, flash, and swap
///@dev for direct pool interaction, this interface is not needed. see [Market.sol] for more details.
interface IPayment {
    /// @notice this is used in createLiquidity, flash, and swap
    /// the caller need to pays specific amounts of tokens to the Market contract.
    function requestToken(address to, address[] memory tokens, uint256[] memory paybackAmounts) external payable;
}
