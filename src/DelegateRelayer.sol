// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import "solidity-bytes-utils/BytesLib.sol";
import "LayerZero/interfaces/ILayerZeroEndpoint.sol";
import "LayerZero/interfaces/ILayerZeroReceiver.sol";
import {RegistryData as Data}  from "./libraries/RegistryData.sol";

abstract contract DelegateRelayer is ILayerZeroReceiver {
    using BytesLib for bytes;

    error NotLayerZero(); // Thrown when !lzEndpoint calls lzReceive()
    error NotDelegateRegistry(); // Thrown if !DelegateRegistry sends a message via LayerZero

    // LayerZero endpoint for the chain contract is deployed to
    ILayerZeroEndpoint public immutable lzEndpoint;

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    // Called by LayerZero infrastructure to deliver a message
    // Chain ID and nonce aren't required. We only allow ourselves to send per chain, so data ordering isn't important
    function lzReceive(
        uint16,
        bytes calldata _srcAddress,
        uint64,
        bytes calldata _payload
    ) external override {
        // lzReceive() must only be called by the LayerZero endpoint
        if (msg.sender != address(lzEndpoint)) {
            revert NotLayerZero();
        }
        // Supporting any chain as origin is possible if we assume registry address will be the same across 
        // all LayerZero-supported chains. This should hold true if CREATE2 functions the same everywhere.
        if (!_srcAddress.equal(abi.encodePacked(address(this)))) {
            revert NotDelegateRegistry();
        }

        _lzReceive(_payload);
    }

    // Overridden in DelegateRegistry to implement payload handling
    function _lzReceive(bytes memory _payload) internal virtual;

    // Helper function to get payload for use in estimateFees() (required to avoid stack too deep)
    function getPayload(
        Data.DelegationType type_,
        bool enable,
        address to,
        address from,
        address contract_,
        uint256 tokenId,
        uint256 amount,
        bytes32 rights
    ) external pure returns (bytes memory payload) {
        payload = _packPayload(type_, enable, to, from, contract_, tokenId, amount, rights);
    }

    // Estimate LayerZero transmission costs for delegation parameters
    function estimateFees(
        uint16 dstChainId,
        bytes calldata payload,
        bool payInZRO,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee) {
        (nativeFee, zroFee) = lzEndpoint.estimateFees(dstChainId, address(this), payload, payInZRO, adapterParams);
    }

    // Handles packing all delegation type parameters for transmitting cross-chain
    // Optimized for sending as little data across LayerZero as necessary
    function _packPayload(
        Data.DelegationType type_,
        bool enable,
        address to,
        address from,
        address contract_,
        uint256 tokenId,
        uint256 amount,
        bytes32 rights
    ) internal pure returns (bytes memory) {
        if (type_ == Data.DelegationType.ALL) {
            if (rights == bytes32("")) {
                return abi.encodePacked(uint8(type_), enable, to, from);
            } else {
                return abi.encodePacked(uint8(type_), enable, to, from, rights);
            }
        } else if (type_ == Data.DelegationType.CONTRACT) {
            if (rights == bytes32("")) {
                return abi.encodePacked(uint8(type_), enable, to, from, contract_);
            } else {
                return abi.encodePacked(uint8(type_), enable, to, from, contract_, rights);
            }
        } else if (type_ == Data.DelegationType.ERC721) {
            if (rights == bytes32("")) {
                return abi.encodePacked(uint8(type_), enable, to, from, contract_, tokenId);
            } else {
                return abi.encodePacked(uint8(type_), enable, to, from, contract_, tokenId, rights);
            }
        } else if (type_ == Data.DelegationType.ERC20) {
            if (rights == bytes32("")) {
                return abi.encodePacked(uint8(type_), to, from, contract_, amount);
            } else {
                return abi.encodePacked(uint8(type_), to, from, contract_, amount, rights);
            }
        } else if (type_ == Data.DelegationType.ERC1155) {
            if (rights == bytes32("")) {
                return abi.encodePacked(uint8(type_), to, from, contract_, tokenId, amount);
            } else {
                return abi.encodePacked(uint8(type_), to, from, contract_, tokenId, amount, rights);
            }
        } else {
            revert();
        }
    }

    // Used to process a cross-chain payload once it is received
    function _unpackPayload(bytes memory _payload) internal pure returns (Data.Delegation memory payload) {
        Data.DelegationType type_ = Data.DelegationType(uint8(_payload[0]));
        // Declare all possible variables
        bool enable;
        address to;
        address from;
        address contract_;
        uint256 tokenId;
        uint256 amount;
        bytes32 rights;

        // Parse optimized payload for relevant variables based on DelegationType
        if (type_ == Data.DelegationType.ALL) {
            enable = (_payload[1] != 0);
            to = _payload.slice(2, 20).toAddress(0);
            from = _payload.slice(22, 20).toAddress(0);
            if (_payload.length > 42) {
                rights = _payload.slice(42, 32).toBytes32(0);
            }
        } else if (type_ == Data.DelegationType.CONTRACT) {
            enable = (_payload[1] != 0);
            to = _payload.slice(2, 20).toAddress(0);
            from = _payload.slice(22, 20).toAddress(0);
            contract_ = _payload.slice(42, 20).toAddress(0);
            if (_payload.length > 62) {
                rights = _payload.slice(62, 32).toBytes32(0);
            }
        } else if (type_ == Data.DelegationType.ERC721) {
            enable = (_payload[1] != 0);
            to = _payload.slice(2, 20).toAddress(0);
            from = _payload.slice(22, 20).toAddress(0);
            contract_ = _payload.slice(42, 20).toAddress(0);
            tokenId = _payload.slice(62, 32).toUint256(0);
            if (_payload.length > 94) {
                rights = _payload.slice(94, 32).toBytes32(0);
            }
        } else if (type_ == Data.DelegationType.ERC20) {
            to = _payload.slice(1, 20).toAddress(0);
            from = _payload.slice(21, 20).toAddress(0);
            contract_ = _payload.slice(41, 20).toAddress(0);
            amount = _payload.slice(61, 32).toUint256(0);
            if (_payload.length > 93) {
                rights = _payload.slice(93, 32).toBytes32(0);
            }
        } else if (type_ == Data.DelegationType.ERC1155) {
            to = _payload.slice(1, 20).toAddress(0);
            from = _payload.slice(21, 20).toAddress(0);
            contract_ = _payload.slice(41, 20).toAddress(0);
            tokenId = _payload.slice(61, 32).toUint256(0);
            amount = _payload.slice(93, 32).toUint256(0);
            if (_payload.length > 125) {
                rights = _payload.slice(125, 32).toBytes32(0);
            }
        } else {
            revert();
        }

        payload = Data.Delegation({
            type_: type_,
            enable: enable,
            to: to,
            from: from,
            contract_: contract_,
            tokenId: tokenId,
            amount: amount,
            rights: rights
        });
    }

    // Sends a payload to the respective chain, relaying all required information to LayerZero's endpoint
    function _lzSend(
        uint16 _dstChainId,
        address _zroPaymentAddress,
        bytes memory _payload,
        uint _nativeFee
    ) private {
        lzEndpoint.send{ value: _nativeFee }(
            _dstChainId,
            abi.encodePacked(address(this)),
            _payload,
            payable(msg.sender),
            _zroPaymentAddress,
            bytes("")
        );
    }

    // Called to relay a delegation to as many chains as specified
    function _relayDelegation(
        uint16[] memory _dstChainIds,
        address _zroPaymentAddress,
        bytes memory _payload,
        uint[] memory _nativeFees
    ) internal {
        for (uint i; i < _dstChainIds.length;) {
            _lzSend(_dstChainIds[i], _zroPaymentAddress, _payload, _nativeFees[i]);
            unchecked { ++i; }
        }
    } 
}