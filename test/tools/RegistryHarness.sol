// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {BytesLib} from "solidity-bytes-utils/BytesLib.sol";
import {DelegateRegistry} from "../../src/DelegateRegistry.sol";
import {RegistryData as Data}  from "../../src/libraries/RegistryData.sol";

/// @dev harness contract that exposes internal registry methods as external ones
contract RegistryHarness is DelegateRegistry {
    using BytesLib for bytes;

    address remoteReg; // Store address of remote registry as we can't emulate two deployments at same address locally
    bytes32[] temporaryStorage;

    // Alter constructor to set new lzEndpoint address
    constructor(address _lzEndpoint) DelegateRegistry(_lzEndpoint) {
        delegations[0][0] = 0;
    }

    // Store remote registry address post-deployment
    function setRemoteReg(address reg) external {
        remoteReg = reg;
    }

    function exposedDelegations(bytes32 hash) external view returns (bytes32[5] memory) {
        return delegations[hash];
    }

    function exposedOutgoingDelegationHashes(address vault) external view returns (bytes32[] memory) {
        return outgoingDelegationHashes[vault];
    }

    function exposedIncomingDelegationHashes(address delegate) external view returns (bytes32[] memory) {
        return incomingDelegationHashes[delegate];
    }

    function exposedPushDelegationHashes(address from, address to, bytes32 delegationHash) external {
        _pushDelegationHashes(from, to, delegationHash);
    }

    function exposedWriteDelegation(bytes32 location, uint256 position, bytes32 data) external {
        _writeDelegation(location, position, data);
    }

    function exposedWriteDelegation(bytes32 location, uint256 position, uint256 data) external {
        _writeDelegation(location, position, data);
    }

    function exposedWriteDelegationAddresses(bytes32 location, address from, address to, address contract_) external {
        _writeDelegationAddresses(location, from, to, contract_);
    }

    function exposedGetValidDelegationsFromHashes(bytes32[] calldata hashes) external returns (Data.Delegation[] memory delegations_) {
        temporaryStorage = hashes;
        return _getValidDelegationsFromHashes(temporaryStorage);
    }

    function exposedGetValidDelegationHashesFromHashes(bytes32[] calldata hashes) external returns (bytes32[] memory validHashes) {
        temporaryStorage = hashes;
        return _getValidDelegationHashesFromHashes(temporaryStorage);
    }

    function exposedLoadDelegationBytes32(bytes32 location, uint256 position) external view returns (bytes32 data) {
        return _loadDelegationBytes32(location, position);
    }

    function exposedLoadDelegationUint(bytes32 location, uint256 position) external view returns (uint256 data) {
        return _loadDelegationUint(location, position);
    }

    function exposedLoadFrom(bytes32 location) external view returns (address from) {
        return _loadFrom(location);
    }

    function exposedValidateFrom(bytes32 location, address from) external view returns (bool) {
        return _validateFrom(location, from);
    }

    function exposedLoadDelegationAddresses(bytes32 location) external view returns (address from, address to, address contract_) {
        return _loadDelegationAddresses(location);
    }

    // Override _lzSend to utilize remote registry address instead of address(this) for local and remote
    function _lzSend(
        uint16 _dstChainId,
        address _zroPaymentAddress,
        bytes memory _payload,
        uint _nativeFee,
        bytes memory _adapterParams
    ) internal override {
        lzEndpoint.send{ value: _nativeFee }(
            _dstChainId,
            abi.encodePacked(remoteReg, address(this)),
            _payload,
            payable(msg.sender),
            _zroPaymentAddress,
            _adapterParams
        );
        emit DelegationRelayed(_dstChainId, _payload);
    }

    // Override lzReceive to utilize remote registry address instead of address(this) for local and remote
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
        if (!_srcAddress.equal(abi.encodePacked(remoteReg, address(this)))) {
            revert NotDelegateRegistry();
        }
        // Process internal message handling
        _lzReceive(_payload);
    }
}
