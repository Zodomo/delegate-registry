// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

library RegistryData {
    /// @notice Delegation type, NONE is used when a delegation does not exist or is revoked
    enum DelegationType {
        NONE,
        ALL,
        CONTRACT,
        ERC721,
        ERC20,
        ERC1155
    }

    /// @notice Struct for returning delegations and relaying data cross-chain
    struct Delegation {
        DelegationType type_;
        bool enable;
        address to;
        address from;
        address contract_;
        bytes32 rights;
        uint256 tokenId;
        uint256 amount;
    }
}