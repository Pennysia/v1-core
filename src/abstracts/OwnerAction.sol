// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.30;

import {IOwnerAction} from "../interfaces/IOwnerAction.sol";
import {PairLibrary} from "../libraries/PairLibrary.sol";
import {Validation} from "../libraries/Validation.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

abstract contract OwnerAction is IOwnerAction {
    address public override owner;
    address public override router;
    bool public override feeSwitch;

    /// @notice Tracks the total reserved balance for each token across all pairs.
    mapping(address => uint256) public override tokenBalances;

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, forbidden());
        _;
    }

    modifier onlyRouter() {
        address _router = router;
        require(msg.sender == _router && _router != address(0), forbidden());
        _;
    }

    function setOwner(address _owner) external override onlyOwner {
        owner = _owner;
    }

    function setRouter(address _router) external override onlyOwner {
        router = _router;
    }

    function setFeeSwitch(bool _feeSwitch) external override onlyOwner {
        feeSwitch = _feeSwitch;
    }

    function getSweepable(address token) public view override returns (uint256) {
        return PairLibrary.getBalance(token) - tokenBalances[token];
    }

    function sweep(address[] calldata tokens, uint256[] calldata amounts, address[] calldata to)
        external
        override
        onlyOwner
    {
        uint256 length = tokens.length;
        Validation.equalLengths(length, amounts.length);
        Validation.equalLengths(length, to.length);
        for (uint256 i; i < length; i++) {
            require(amounts[i] <= getSweepable(tokens[i]), excessiveSweep());
            TransferHelper.safeTransfer(tokens[i], to[i], amounts[i]);
        }
        emit Sweep(msg.sender, to, tokens, amounts);
    }
}
