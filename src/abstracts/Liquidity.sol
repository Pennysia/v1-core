// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.30;

import {ILiquidity} from "../interfaces/ILiquidity.sol";
import {Deadline} from "./Deadline.sol";

/// @notice Pennysia's LP token implementation
/// @dev modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol)

abstract contract Liquidity is ILiquidity, Deadline {
    /*//////////////////////////////////////////////////////////////
                             STORAGE
    //////////////////////////////////////////////////////////////*/

    //id -> supply
    mapping(uint256 => uint256) public override totalSupply;

    mapping(uint256 => uint256) public override totalVoteWeight;

    //acccount -> id -> balance
    mapping(address => mapping(uint256 => uint256)) public override balanceOf;

    //account -> id -> voteFee
    mapping(address => mapping(uint256 => uint256)) public override voteOf;

    //owner -> spender -> id -> allowance
    mapping(address => mapping(address => mapping(uint256 => uint256))) public override allowance;

    //owner -> operator -> boolean
    mapping(address => mapping(address => bool)) public override isOperator;

    //owner -> id -> nonce
    mapping(address => mapping(uint256 => uint256)) public override nonces;

    uint256 private immutable INITIAL_CHAIN_ID;
    bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor() {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               LOGIC
    //////////////////////////////////////////////////////////////*/

    function name() public pure override returns (string memory) {
        return "Pennysia Liquidity";
    }

    function symbol() public pure override returns (string memory) {
        return "PLP";
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function approve(address spender, uint256 id, uint256 amount) public override returns (bool) {
        allowance[msg.sender][spender][id] = amount;
        emit Approval(msg.sender, spender, id, amount);
        return true;
    }

    function setOperator(address operator, bool approved) public override returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    function transfer(address to, uint256 id, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, id, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 id, uint256 amount) public override returns (bool) {
        if (msg.sender != from && !isOperator[from][msg.sender]) {
            uint256 allowed = allowance[from][msg.sender][id];
            if (allowed != type(uint256).max) allowance[from][msg.sender][id] = allowed - amount;
        }
        _transfer(from, to, id, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 id, uint256 amount) private {
        if (to != address(0)) {
            balanceOf[from][id] -= amount;
            // Cannot overflow because the sum of all user
            // balances can't exceed the max uint256 value.
            unchecked {
                balanceOf[to][id] += amount;
            }
            emit Transfer(from, to, id, amount);
        } else {
            _burn(from, id, amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              EIP-2612
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 id,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override ensure(deadline) returns (bool) {
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            // Recover signer and validate.
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                0x41b82e2b5a0c36576b0cbe551120f192388f4a0e73168b730f27a8a467e1f79f, // keccak256("Permit(address owner,address spender,uint256 id,uint256 value,uint256 nonce,uint256 deadline)")
                                owner,
                                spender,
                                id,
                                value,
                                nonces[owner][id]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner);
            allowance[owner][spender][id] = value;
        }

        emit Approval(owner, spender, id, value);
        return true;
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x8485c8f9ff1831604071989682a90eadc69f950358057c3b4a600e0942b750fa, // keccak256(bytes(name))
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256("1")
                block.chainid,
                address(this)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                              Mint & Burn
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 id, uint256 amount) internal {
        totalSupply[id] += amount;
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to][id] += amount;
        }
        emit Transfer(address(0), to, id, amount);
    }

    function _burn(address from, uint256 id, uint256 amount) internal {
        balanceOf[from][id] -= amount;
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply[id] -= amount;
        }
        emit Transfer(from, address(0), id, amount);
    }
}
