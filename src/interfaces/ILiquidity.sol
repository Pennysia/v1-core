// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.30;

interface ILiquidity {
    event Transfer(address indexed from, address indexed to, uint256 indexed id, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed owner, address indexed operator, bool approved);

    /// @notice Returns the name of the token
    /// @return The name of the token
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token
    /// @return The symbol of the token
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals used by the token
    /// @return The number of decimals
    function decimals() external view returns (uint8);

    /// @notice Returns the total supply of LP tokens
    /// @param id The tokenId
    /// @return The total supply of the token
    function totalSupply(uint256 id) external view returns (uint256);

    /// @notice Returns the total vote weight of the token
    /// @param id The tokenId
    /// @return The total vote weight of the token
    function totalVoteWeight(uint256 id) external view returns (uint256);

    /// @notice Returns the balance of an account for a token
    /// @param account The address of the account
    /// @param id The tokenId
    /// @return The balance of the account
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /// @notice Returns the vote weight of an account for a token
    /// @param account The address of the account
    /// @param id The tokenId
    /// @return The vote weight of the account
    function voteOf(address account, uint256 id) external view returns (uint256);

    /// @notice Returns the allowance of an account for a token
    /// @param owner The address of the account
    /// @param spender The address of the spender
    /// @param id The tokenId
    /// @return The allowance of the account
    function allowance(address owner, address spender, uint256 id) external view returns (uint256);

    /// @notice Returns the operator status of an account for a token
    /// @param owner The address of the account
    /// @param operator The address of the operator
    /// @return The operator status of the account
    function isOperator(address owner, address operator) external view returns (bool);

    /// @notice Approves an account to spend a token
    /// @param spender The address of the spender
    /// @param id The tokenId
    /// @param amount The amount of the token to approve
    /// @return A boolean indicating whether the operation succeeded
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);

    /// @notice Sets the operator status of an account for a token
    /// @param operator The address of the operator
    /// @param approved The operator status
    /// @return A boolean indicating whether the operation succeeded
    function setOperator(address operator, bool approved) external returns (bool);

    /// @notice Transfers a token to an account
    /// @param to The address of the recipient
    /// @param id The tokenId
    /// @param amount The amount of the token to transfer
    /// @return A boolean indicating whether the operation succeeded
    function transfer(address to, uint256 id, uint256 amount) external returns (bool);

    /// @notice Transfers a token from an account to another account
    /// @param from The address of the sender
    /// @param to The address of the recipient
    /// @param id The tokenId
    /// @param amount The amount of the token to transfer
    /// @return A boolean indicating whether the operation succeeded
    function transferFrom(address from, address to, uint256 id, uint256 amount) external returns (bool);

    /// @notice Approves a spender to transfer tokens using a signature
    /// @param owner The address of the token owner
    /// @param spender The address to approve or revoke permission for
    /// @param id The tokenId
    /// @param value the block timestamp limit
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
    ) external returns (bool);

    /// @notice Returns the current nonce for an owner
    /// @param owner The address to query the nonce of
    /// @param id The tokenId
    /// @return The current nonce of the owner
    function nonces(address owner, uint256 id) external view returns (uint256);

    /// @notice Returns the domain separator used in the permit signature
    /// @return The domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
