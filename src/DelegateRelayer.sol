// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import "solidity-bytes-utils/BytesLib.sol";
import "LayerZero/interfaces/ILayerZeroEndpoint.sol";
import "LayerZero/interfaces/ILayerZeroReceiver.sol";

abstract contract DelegateRelayer is ILayerZeroReceiver {
    using BytesLib for bytes;

    error NotLayerZero();
    error NotDelegateRegistry();

    ILayerZeroEndpoint public immutable lzEndpoint;

    constructor(address _endpoint) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
    }

    function lzReceive(
        uint16,
        bytes calldata _srcAddress,
        uint64,
        bytes calldata _payload
    ) public override {
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

    function _lzReceive(bytes memory _payload) internal virtual;

    function _lzSend(
        uint16 _dstChainId,
        address _zroPaymentAddress,
        bytes memory _payload,
        bytes memory _adapterParams,
        uint _nativeFee
    ) internal {
        lzEndpoint.send{ value: _nativeFee }(
            _dstChainId,
            abi.encodePacked(address(this)),
            _payload,
            payable(msg.sender),
            _zroPaymentAddress,
            _adapterParams
        );
    }
}