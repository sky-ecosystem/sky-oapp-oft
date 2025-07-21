// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "forge-std/console.sol";

import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { GovernanceEVMCodecLibraryHelper } from "./helpers/GovernanceEVMCodecLibraryHelper.sol";

contract GovernanceMessageEVMCodecTest is TestHelperOz5 {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant GOVERNED_CONTRACT_OFFSET = ACTION_OFFSET + 1;
    uint8 private constant CALLDATA_OFFSET = GOVERNED_CONTRACT_OFFSET + 20;

    GovernanceEVMCodecLibraryHelper helper = new GovernanceEVMCodecLibraryHelper();

    function test_encoding() public {
        address mintReceiver = makeAddr("mintReceiver");
        address governedContract = makeAddr("governedContract");

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            governedContract: governedContract,
            callData: abi.encodeWithSelector(ERC20Mock.mint.selector, mintReceiver, 100)
        });

        bytes memory encoded = GovernanceMessageEVMCodec.encode(message);
        console.logBytes(encoded);

        GovernanceMessageEVMCodec.GovernanceMessage memory decoded = helper.decode(encoded);
        assertEq(decoded.action, message.action);
        assertEq(decoded.governedContract, message.governedContract);
        assertEq(decoded.callData, message.callData);

        console.log("decoded.action: %s", decoded.action);
        console.log("decoded.governedContract: %s", decoded.governedContract);
        console.log("decoded.callData: %s", vm.toString(abi.encode(decoded.callData)));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_invalid_action_encoding() public {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.UNDEFINED),
            governedContract: makeAddr("governedContract"),
            callData: abi.encodeWithSelector(ERC20Mock.mint.selector, makeAddr("mintReceiver"), 100)
        });

        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.InvalidAction.selector, uint8(GovernanceAction.UNDEFINED)));
        GovernanceMessageEVMCodec.encode(message);
    }

    function test_invalid_action_decoding() public {
        bytes memory message = new bytes(CALLDATA_OFFSET);
        message[ACTION_OFFSET] = bytes1(uint8(GovernanceAction.UNDEFINED));
        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.InvalidAction.selector, uint8(GovernanceAction.UNDEFINED)));
        helper.decode(message);

        message[ACTION_OFFSET] = bytes1(uint8(GovernanceAction.EVM_CALL));
        helper.decode(message);
    }

    function test_payload_encoding() public {
        bytes memory callData = new bytes(uint32(type(uint16).max) + 1);
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            governedContract: makeAddr("governedContract"),
            callData: callData
        });

        GovernanceMessageEVMCodec.encode(message);
    }

    function test_invalid_message_length(uint8 messageLength) public {
        vm.assume(messageLength < CALLDATA_OFFSET);
        bytes memory message = new bytes(messageLength);
        
        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageEVMCodec.InvalidMessageLength.selector));
        helper.decode(message);
    }
}
