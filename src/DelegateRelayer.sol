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

    // Handles packing all delegation type parameters for transmitting cross-chain
    function _packPayload(
        Data.DelegationType type_,
        bool enable,
        address from,
        address to,
        address contract_,
        uint256 tokenId,
        uint256 amount,
        bytes32 rights
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(type_), enable, to, from, contract_, rights, tokenId, amount);
    }

    // Used to process a cross-chain payload once it is received
    function _unpackPayload(bytes memory _payload) internal pure returns (Data.Delegation memory payload) {
        Data.DelegationType type_ = Data.DelegationType(uint8(_payload[0]));
        bool enable = (_payload[1] != 0);
        address to = _payload.slice(2, 20).toAddress(0);
        address from = _payload.slice(22, 20).toAddress(0);
        address contract_ = _payload.slice(42, 20).toAddress(0);
        bytes32 rights = _payload.slice(62, 32).toBytes32(0);
        uint256 tokenId = _payload.slice(94, 32).toUint256(0);
        uint256 amount = _payload.slice(126, 32).toUint256(0);

        payload = Data.Delegation({
            type_: type_,
            enable: enable,
            to: to,
            from: from,
            contract_: contract_,
            rights: rights,
            tokenId: tokenId,
            amount: amount
        });
    }

    // Sends a payload to the respective chain, relaying all required information to LayerZero's endpoint
    function _lzSend(
        uint16 _dstChainId,
        address _zroPaymentAddress,
        bytes memory _payload,
        uint _nativeFee
    ) internal {
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