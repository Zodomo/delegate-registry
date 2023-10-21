// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import "solidity-bytes-utils/BytesLib.sol";
import "LayerZero/interfaces/ILayerZeroEndpoint.sol";
import "LayerZero/interfaces/ILayerZeroReceiver.sol";

abstract contract DelegateRelayer is ILayerZeroReceiver {
    using BytesLib for bytes;

    error NotLayerZero();
    error NotDelegateRegistry();
    error InsufficientPayment();

    enum Type {
        ALL,
        CONTRACT,
        ERC721,
        ERC20,
        ERC1155
    }

    struct Payload {
        bool enable;
        Type type_;
        address from;
        address to;
        address contract_;
        uint256 tokenId;
        uint256 amount;
        bytes32 rights;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

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

    function _lzReceive(bytes memory _payload) internal virtual;

    function _packPayload(
        bool enable,
        Type type_,
        address from,
        address to,
        address contract_,
        uint256 tokenId,
        uint256 amount,
        bytes32 rights
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(enable, uint8(type_), from, to, contract_, tokenId, amount, rights);
    }

    function _unpackPayload(bytes memory _payload) internal pure returns (Payload memory payload) {
        bool enable = (_payload[0] != 0);
        Type type_ = Type(uint8(_payload[1]));
        address from = _payload.slice(2, 20).toAddress(0);
        address to = _payload.slice(22, 20).toAddress(0);
        address contract_ = _payload.slice(42, 20).toAddress(0);
        uint256 tokenId = _payload.slice(62, 32).toUint256(0);
        uint256 amount = _payload.slice(94, 32).toUint256(0);
        bytes32 rights = _payload.slice(126, 32).toBytes32(0);

        payload = Payload({
            enable: enable,
            type_: type_,
            from: from,
            to: to,
            contract_: contract_,
            tokenId: tokenId,
            amount: amount,
            rights: rights
        });
    }

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

    function _relayDelegation(
        address _zroPaymentAddress,
        bytes memory _payload,
        uint[] memory _nativeFees
    ) internal {
        uint totalFees;
        for (uint i; i < _nativeFees.length;) {
            unchecked {
                totalFees += _nativeFees[i];
                ++i;
            }
        }
        if (totalFees < msg.value) {
            revert InsufficientPayment();
        }
        // TODO: Relay to other chains
    } 
}