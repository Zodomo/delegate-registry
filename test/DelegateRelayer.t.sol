// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {RegistryHarness} from "./tools/RegistryHarness.sol";
import {RegistryData as Data}  from "../src/libraries/RegistryData.sol";
import {LZEndpointMock} from "solidity-examples/lzApp/mocks/LZEndpointMock.sol";
import {BytesLib} from "solidity-bytes-utils/BytesLib.sol";

// Initial testing of LayerZero integration via LZEndpointMock
// RegistryHarness is deployed as it overrides logic requiring address(this) be the same in each deployment
contract DelegateRegistryTest is Test {
    LZEndpointMock public lzEndpointA;
    LZEndpointMock public lzEndpointB;
    RegistryHarness public regA;
    RegistryHarness public regB;
    bytes32 public rights = "";
    bytes public params = "";

    function setUp() public {
        // Deploy LZ mock endpoints first
        lzEndpointA = new LZEndpointMock(1);
        lzEndpointB = new LZEndpointMock(2);
        // Configure each RegistryHarness to be aware of each other
        regA = new RegistryHarness(address(lzEndpointA));
        regB = new RegistryHarness(address(lzEndpointB));
        regA.setRemoteReg(address(regB));
        regB.setRemoteReg(address(regA));
        // Configure mock endpoints to be aware of proper routing
        lzEndpointA.setDestLzEndpoint(address(regB), address(lzEndpointB));
        lzEndpointB.setDestLzEndpoint(address(regA), address(lzEndpointA));
    }

    // Generate sample payload
    function regAGetPayloadAll() public view returns (bytes memory payload) {
        payload = regA.getPayload(
            Data.DelegationType.ALL,
            true,
            address(22222),
            address(11111),
            address(0),
            0,
            0,
            rights
        );
    }

    // Confirm sample payload isn't blank bytes array
    function testRegAGetPayloadAll() public view returns (bytes memory payload) {
        payload = regAGetPayloadAll();
        require(!BytesLib.equal(payload, (bytes(""))), "payload generation failed");
    }
    
    // Confirm endpoint returns fee estimate for inputs
    function testRegAEstimateFees() public view returns (uint256 nativeFee, uint256 zroFee) {
        (nativeFee, zroFee) = regA.estimateFees(2, regAGetPayloadAll(), false, params);
    }

    // Process relaying delegation state across chain and validate remote state
    function testRegADelegateAll() public returns (bytes32 hash) {
        // Prepare LZ-related delegation inputs
        uint16[] memory dstChainIds = new uint16[](1);
        dstChainIds[0] = 2;
        uint[] memory nativeFees = new uint[](1);
        (nativeFees[0], ) = testRegAEstimateFees();
        bytes[] memory adapterParams = new bytes[](1);
        adapterParams[0] = params;
        // Act as address(11111) in committing delegation
        vm.deal(address(11111), 10 ether);
        vm.prank(address(11111));
        hash = regA.delegateAll{ value: nativeFees[0] }(
            address(22222),
            rights,
            true,
            dstChainIds,
            address(0),
            nativeFees,
            adapterParams
        );
        // Validate that delegation occurred by verifying delegate hash and remote data storage
        require(!BytesLib.equal(abi.encodePacked(hash), (bytes(""))), "delegation failed");
        require(regB.checkDelegateForAll(address(22222), address(11111), rights), "delegate status error");
        bytes32[] memory hashes = new bytes32[](1);
        hashes[0] = hash;
        Data.Delegation[] memory delegations = regB.getDelegationsFromHashes(hashes);
        require(delegations[0].type_ == Data.DelegationType.ALL, "delegation type error");
        require(delegations[0].enable == true, "delegation status error");
        require(delegations[0].to == address(22222), "delegation to error");
        require(delegations[0].from == address(11111), "delegation from error");
        require(delegations[0].contract_ == address(0), "delegation contract error");
        require(delegations[0].rights == rights, "delegation rights error");
        require(delegations[0].tokenId == 0, "delegation tokenId error");
        require(delegations[0].amount == 0, "delegation amount error");
    }
}