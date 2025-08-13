// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.28;

import {ILiquidity} from "../interfaces/ILiquidity.sol";
import {Deadline} from "./Deadline.sol";
/**
 * @title Pennysia's liquidity token
 * @notice Implementation of the Pennysia's liqudiity token, using minimal multi-token structure unique to the protocol.
 * @dev This contract implements a TTL (Time-To-Live) based token approval system instead of the standard ERC20 amount-based allowance.
 *      The allowance mapping stores block timestamps as values, where a timestamp greater than the current block.timestamp
 *      indicates an active approval.
 */

abstract contract Liquidity is ILiquidity, Deadline {
    /*//////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Total supply of LP tokens by poolId
    mapping(uint256 => LpInfo) internal _totalSupply;

    /// @notice Mapping of account addresses with poolId to their LP token balances
    mapping(address => mapping(uint256 => LpInfo)) internal _balances;

    /// @notice Tracks the timestamp-based allowances for token transfers
    /// @dev Uses block.timestamp as the approval metric. A timestamp greater than current block.timestamp indicates an active approval.
    ///      This implements a TTL (Time-To-Live) based approval system where approvals automatically expire.
    mapping(address => mapping(address => mapping(uint256 => uint256)))
        public
        override allowance;

    /// @notice Mapping of account addresses with poolId to their nonces for permit functionality
    mapping(address => mapping(uint256 => uint256)) public override nonces;

    /// @notice Initial chain ID for domain separator computation
    uint256 private immutable INITIAL_CHAIN_ID;

    /// @notice Initial domain separator for permit functionality
    bytes32 private immutable INITIAL_DOMAIN_SEPARATOR;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice contract constructor
    constructor() {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                              ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the name of the token
    function name() public pure override returns (string memory) {
        return "Pennysia Liquidity";
    }

    /// @notice Returns the symbol of the token
    function symbol() public pure override returns (string memory) {
        return "Pennysia-LP";
    }

    /// @notice Returns the number of decimals used by the token
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /// @notice Returns the total supply of LP tokens
    function totalSupply(
        uint256 poolId
    )
        public
        view
        override
        returns (uint128 longX, uint128 shortX, uint128 longY, uint128 shortY)
    {
        return (
            _totalSupply[poolId].longX,
            _totalSupply[poolId].shortX,
            _totalSupply[poolId].longY,
            _totalSupply[poolId].shortY
        );
    }

    function balanceOf(
        address account,
        uint256 poolId
    )
        public
        view
        override
        returns (uint128 longX, uint128 shortX, uint128 longY, uint128 shortY)
    {
        return (
            _balances[account][poolId].longX,
            _balances[account][poolId].shortX,
            _balances[account][poolId].longY,
            _balances[account][poolId].shortY
        );
    }

    /// @notice Approves or revokes permission for a spender to transfer tokens
    function approve(
        address spender,
        uint256 poolId,
        uint256 value
    ) public override returns (bool) {
        address owner = msg.sender;
        allowance[owner][spender][poolId] = value;
        emit Approval(owner, spender, poolId, value);
        return true;
    }

    /// @notice Transfers LP tokens to another address
    /// @dev if 'to' is the address(0), it will burn the tokens instead of transferring.
    function transfer(
        address to,
        uint256 poolId,
        uint128 longX,
        uint128 shortX,
        uint128 longY,
        uint128 shortY
    ) public returns (bool) {
        require(to != address(this), InvalidAddress());
        if (to != address(0)) {
            LpInfo storage lpInfo_from = _balances[msg.sender][poolId];
            lpInfo_from.longX -= longX;
            lpInfo_from.shortX -= shortX;
            lpInfo_from.longY -= longY;
            lpInfo_from.shortY -= shortY;

            LpInfo storage lpInfo_to = _balances[to][poolId];
            // Cannot overflow because the sum of all user
            // balances can't exceed the max uint256 value.
            unchecked {
                lpInfo_to.longX += longX;
                lpInfo_to.shortX += shortX;
                lpInfo_to.longY += longY;
                lpInfo_to.shortY += shortY;
            }
            emit Transfer(msg.sender, to, poolId, longX, shortX, longY, shortY);
        } else {
            _burn(msg.sender, poolId, longX, shortX, longY, shortY);
        }
        return true;
    }

    /// @notice Transfers LP tokens from one address to another
    /// @dev if 'to' is the address(0), it will burn the tokens instead of transferring.
    function transferFrom(
        address from,
        address to,
        uint256 poolId,
        uint128 longX,
        uint128 shortX,
        uint128 longY,
        uint128 shortY
    ) public returns (bool) {
        require(to != address(this), InvalidAddress());
        require(
            allowance[from][msg.sender][poolId] >= block.timestamp,
            InsufficientAllowance()
        );
        if (to != address(0)) {
            LpInfo storage lpInfo_from = _balances[from][poolId];
            lpInfo_from.longX -= longX;
            lpInfo_from.shortX -= shortX;
            lpInfo_from.longY -= longY;
            lpInfo_from.shortY -= shortY;

            LpInfo storage lpInfo_to = _balances[to][poolId];
            // Cannot overflow because the sum of all user
            // balances can't exceed the max uint256 value.
            unchecked {
                lpInfo_to.longX += longX;
                lpInfo_to.shortX += shortX;
                lpInfo_to.longY += longY;
                lpInfo_to.shortY += shortY;
            }
            emit Transfer(from, to, poolId, longX, shortX, longY, shortY);
        } else {
            _burn(from, poolId, longX, shortX, longY, shortY);
        }

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              EIP-2612
    //////////////////////////////////////////////////////////////*/

    /// @notice Approves a spender to transfer tokens using a signature
    function permit(
        address owner,
        address spender,
        uint256 poolId,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public override ensure(deadline) returns (bool) {
        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    "Permit(address owner,address spender,uint256 poolId,uint256 value,uint256 nonce,uint256 deadline)"
                                ),
                                owner,
                                spender,
                                poolId,
                                value,
                                nonces[owner][poolId]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(
                recoveredAddress != address(0) && recoveredAddress == owner,
                InvalidAddress()
            );
            allowance[owner][spender][poolId] = value;
        }

        emit Approval(owner, spender, poolId, value);
        return true;
    }

    /// @notice Returns the domain separator used in the permit signature
    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return
            block.chainid == INITIAL_CHAIN_ID
                ? INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    /// @notice Computes the domain separator for permit functionality
    function computeDomainSeparator() private view returns (bytes32) {
        return
            keccak256(
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

    /// @notice Mints new LP tokens to an address
    function _mint(
        address to,
        uint256 poolId,
        uint128 longX,
        uint128 shortX,
        uint128 longY,
        uint128 shortY
    ) internal {
        LpInfo storage lpInfo_total = _totalSupply[poolId];
        lpInfo_total.longX += longX;
        lpInfo_total.shortX += shortX;
        lpInfo_total.longY += longY;
        lpInfo_total.shortY += shortY;

        LpInfo storage lpInfo_bal = _balances[to][poolId];
        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            lpInfo_bal.longX += longX;
            lpInfo_bal.shortX += shortX;
            lpInfo_bal.longY += longY;
            lpInfo_bal.shortY += shortY;
        }

        emit Transfer(address(0), to, poolId, longX, shortX, longY, shortY);
    }

    /// @notice Burns LP tokens from an address
    function _burn(
        address from,
        uint256 poolId,
        uint128 longX,
        uint128 shortX,
        uint128 longY,
        uint128 shortY
    ) internal {
        LpInfo storage lpInfo_bal = _balances[from][poolId];
        lpInfo_bal.longX -= longX;
        lpInfo_bal.shortX -= shortX;
        lpInfo_bal.longY -= longY;
        lpInfo_bal.shortY -= shortY;

        LpInfo storage lpInfo_total = _totalSupply[poolId];
        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            lpInfo_total.longX -= longX;
            lpInfo_total.shortX -= shortX;
            lpInfo_total.longY -= longY;
            lpInfo_total.shortY -= shortY;
        }

        emit Transfer(from, address(0), poolId, longX, shortX, longY, shortY);
    }
}
