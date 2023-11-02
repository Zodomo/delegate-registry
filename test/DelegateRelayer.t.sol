// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {Test} from "forge-std/Test.sol";
import {RegistryHarness} from "./tools/RegistryHarness.sol";
import {IDelegateRegistry} from "src/IDelegateRegistry.sol";
import {LZEndpointMock} from "solidity-examples/lzApp/mocks/LZEndpointMock.sol";

contract DelegateRegistryTest is Test {
    LZEndpointMock public lzEndpointA;
    LZEndpointMock public lzEndpointB;
    RegistryHarness public regA;
    RegistryHarness public regB;
    bytes32 public rights = "";

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
}