// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "forge-std/console.sol";

import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceControllerOApp } from "../../contracts/GovernanceControllerOApp.sol";
import { MockCodec } from "./mocks/MockCodec.sol";

contract GovernanceMessageEVMCodecTest is TestHelperOz5 {
    MockCodec mockCodec = new MockCodec();

    function test_encoding() public {
        address mintReceiver = makeAddr("mintReceiver");
        address governedContract = makeAddr("governedContract");
        address originCaller = makeAddr("originCaller");

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceControllerOApp.GovernanceAction.EVM_CALL),
            dstEid: 1,
            originCaller: addressToBytes32(originCaller),
            governedContract: governedContract,
            callData: abi.encodeWithSelector(ERC20Mock.mint.selector, mintReceiver, 100)
        });

        bytes memory encoded = GovernanceMessageEVMCodec.encode(message);
        console.logBytes(encoded);

        GovernanceMessageEVMCodec.GovernanceMessage memory decoded = mockCodec.decode(encoded);
        assertEq(decoded.action, message.action);
        assertEq(decoded.dstEid, message.dstEid);
        assertEq(decoded.originCaller, message.originCaller);
        assertEq(decoded.governedContract, message.governedContract);
        assertEq(decoded.callData, message.callData);

        console.log("decoded.action: %s", decoded.action);
        console.log("decoded.dstEid: %s", decoded.dstEid);
        console.log("decoded.originCaller: %s", vm.toString(decoded.originCaller));
        console.log("decoded.governedContract: %s", decoded.governedContract);
        console.log("decoded.callData: %s", vm.toString(abi.encode(decoded.callData)));
    }
}