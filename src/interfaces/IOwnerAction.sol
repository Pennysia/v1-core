// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.30;

interface IOwnerAction {
    /// @notice Error thrown when caller is not authorized.
    error forbidden();
    /// @notice Error thrown when sweep amount exceeds available.
    error excessiveSweep();

    /// @notice Emitted when excess tokens are swept.
    /// @param sender Caller (owner).
    /// @param to Recipients.
    /// @param tokens Tokens swept.
    /// @param amounts Amounts swept.
    event Sweep(address indexed sender, address[] to, address[] tokens, uint256[] amounts);

    /// @notice The owner of the contract, with administrative privileges like setting new owner or sweeping excess tokens.
    function owner() external view returns (address);

    /// @notice The router of the contract, with administrative privileges like setting new router or sweeping excess tokens.
    function router() external view returns (address);

    /// @notice The deployer fee switch of the contract, with administrative privileges like setting new deployer fee switch.
    function feeSwitch() external view returns (bool);

    /// @notice Sets new owner.
    /// @param _owner New owner address.
    function setOwner(address _owner) external;

    /// @notice Sets new router.
    /// @param _router New router address.
    function setRouter(address _router) external;

    /// @notice Turn on/off the deployer fee switch.
    /// @param _feeSwitch True to turn on, False to turn off.
    function setFeeSwitch(bool _feeSwitch) external;

    /// @notice Sweeps excess tokens.
    /// @param tokens Tokens to sweep.
    /// @param amounts Amounts.
    /// @param to Recipients.
    function sweep(address[] calldata tokens, uint256[] calldata amounts, address[] calldata to) external;

    /// @notice Gets sweepable amount for a token.
    /// @param token Token address.
    /// @return Amount.
    function getSweepable(address token) external view returns (uint256);

    /// @notice Gets reserved balance for a token.
    /// @param token Token address.
    /// @return Balance.
    function tokenBalances(address token) external view returns (uint256);
}
