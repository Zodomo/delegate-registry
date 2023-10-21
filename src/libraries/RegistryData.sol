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

    /// @notice Struct for returning delegations
    struct Delegation {
        DelegationType type_;
        address to;
        address from;
        bytes32 rights;
        address contract_;
        uint256 tokenId;
        uint256 amount;
    }

    // All relevant portions of a delegation action to send via LayerZero
    struct Payload {
        DelegationType type_;
        bool enable;
        address from;
        address to;
        address contract_;
        uint256 tokenId;
        uint256 amount;
        bytes32 rights;
    }
}