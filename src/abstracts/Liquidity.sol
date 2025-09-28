// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.30;

import {ILiquidity} from "../interfaces/ILiquidity.sol";
import {Deadline} from "./Deadline.sol";

abstract contract Liquidity is ILiquidity, Deadline {
    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    //id -> supply
    mapping(uint256 => uint256) public totalSupply;

    //acccount -> id -> balance
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    //owner -> spender -> id -> allowance
    mapping(address => mapping(address => mapping(uint256 => uint256))) public override allowance;

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
                              ERC20 LOGIC
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

    function transfer(address to, uint256 id, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, id, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 id, uint256 amount) public returns (bool) {
        allowance[from][msg.sender][id] -= amount;
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

    /// @notice Approves a spender to transfer tokens using a signature
    /// @param owner The address of the token owner
    /// @param spender The address to approve or revoke permission for
    /// @param id The tokenId
    /// @param value The token amount
    /// @param deadline The time at which the signature expires
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    /// @return A boolean indicating whether the operation succeeded
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
                                keccak256(
                                    "Permit(address owner,address spender,uint256 id,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
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

    /// @notice Returns the domain separator used in the permit signature
    /// @return The domain separator
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    /// @notice Computes the domain separator for permit functionality
    function computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, //keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x8485c8f9ff1831604071989682a90eadc69f950358057c3b4a600e0942b750fa, //keccak256(bytes(name))
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, //keccak256("1")
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
