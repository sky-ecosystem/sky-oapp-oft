// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "forge-std/console.sol";

import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { MockCodec } from "../mocks/MockCodec.sol";
import { GovernanceEVMCodecLibraryHelper } from "./helpers/GovernanceEVMCodecLibraryHelper.sol";

contract GovernanceMessageEVMCodecTest is TestHelperOz5 {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant DST_EID_OFFSET = ACTION_OFFSET + 1;
    uint8 private constant ORIGIN_CALLER_OFFSET = DST_EID_OFFSET + 4;
    uint8 private constant GOVERNED_CONTRACT_OFFSET = ORIGIN_CALLER_OFFSET + 32;
    uint8 private constant CALLDATA_OFFSET = GOVERNED_CONTRACT_OFFSET + 20;

    MockCodec mockCodec = new MockCodec();
    GovernanceEVMCodecLibraryHelper helper = new GovernanceEVMCodecLibraryHelper();

    function test_encoding() public {
        address mintReceiver = makeAddr("mintReceiver");
        address governedContract = makeAddr("governedContract");
        address originCaller = makeAddr("originCaller");

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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

    /// forge-config: default.allow_internal_expect_revert = true
    function test_invalid_action() public {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.UNDEFINED),
            dstEid: 1,
            originCaller: addressToBytes32(makeAddr("originCaller")),
            governedContract: makeAddr("governedContract"),
            callData: abi.encodeWithSelector(ERC20Mock.mint.selector, makeAddr("mintReceiver"), 100)
        });

        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.InvalidAction.selector, uint8(GovernanceAction.UNDEFINED)));
        GovernanceMessageEVMCodec.encode(message);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_payload_too_long() public {
        bytes memory callData = new bytes(uint32(type(uint16).max) + 1);
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: 1,
            originCaller: addressToBytes32(makeAddr("originCaller")),
            governedContract: makeAddr("governedContract"),
            callData: callData
        });

        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.PayloadTooLong.selector, callData.length));
        GovernanceMessageEVMCodec.encode(message);
    }

    function test_invalid_message_length(uint8 messageLength) public {
        vm.assume(messageLength < CALLDATA_OFFSET);
        bytes memory message = new bytes(messageLength);
        
        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.InvalidMessageLength.selector));
        helper.decode(message);
    }
}
