// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {RegistryHarness} from "./tools/RegistryHarness.sol";
import {RegistryData as Data}  from "../src/libraries/RegistryData.sol";
import {LZEndpointMock} from "solidity-examples/lzApp/mocks/LZEndpointMock.sol";
import {BytesLib} from "solidity-bytes-utils/BytesLib.sol";

contract DelegateRegistryTest is Test {
    LZEndpointMock public lzEndpointA;
    LZEndpointMock public lzEndpointB;
    RegistryHarness public regA;
    RegistryHarness public regB;
    bytes32 public rights = "";
    bytes public params = "";

    function setUp() public {
        lzEndpointA = new LZEndpointMock(1);
        lzEndpointB = new LZEndpointMock(2);
        regA = new RegistryHarness(address(lzEndpointA));
        regB = new RegistryHarness(address(lzEndpointB));
        regA.setRemoteReg(address(regB));
        regB.setRemoteReg(address(regA));
        lzEndpointA.setDestLzEndpoint(address(regB), address(lzEndpointB));
        lzEndpointB.setDestLzEndpoint(address(regA), address(lzEndpointA));
    }

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

    function testRegAGetPayloadAll() public view returns (bytes memory payload) {
        payload = regAGetPayloadAll();
        require(!BytesLib.equal(payload, (bytes(""))), "payload generation failed");
    }

    function testRegAEstimateFees() public view returns (uint256 nativeFee, uint256 zroFee) {
        (nativeFee, zroFee) = regA.estimateFees(2, regAGetPayloadAll(), false, params);
    }

    function testRegADelegateAll() public returns (bytes32 hash) {
        uint16[] memory dstChainIds = new uint16[](1);
        dstChainIds[0] = 2;
        uint[] memory nativeFees = new uint[](1);
        (nativeFees[0], ) = testRegAEstimateFees();
        bytes[] memory adapterParams = new bytes[](1);
        adapterParams[0] = params;
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
    }
}