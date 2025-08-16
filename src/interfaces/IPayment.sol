// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.28;

/// @title IPayment
///@notice these are payment request callbacks covering mint, burn, flash, and swap
///@dev for direct pool interaction, this interface is not needed. see [Market.sol] for more details.
interface IPayment {
    /// @notice this is used in createLiquidity, flash, and swap
    /// the caller need to pays specific amounts of tokens to the Market contract.
    function requestToken(address to, address[] memory tokens, uint256[] memory paybackAmounts) external payable;

    /// @notice this is used in burn
    /// the caller need to pays specific amounts of liquidity tokens by transferring them to address(0).
    /// See Liquidity.sol for more details.
    function requestLiquidity(
        address to,
        uint256 poolId,
        uint128 amountForLongX,
        uint128 amountForShortX,
        uint128 amountForLongY,
        uint128 amountForShortY
    ) external;
}
