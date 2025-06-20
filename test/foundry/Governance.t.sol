// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import "forge-std/console.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { GovernanceControllerOApp } from "../../contracts/GovernanceControllerOApp.sol";
import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { MockControlledContract } from "../mocks/MockControlledContract.sol";
import { MockGovernanceRelay } from "../mocks/MockGovernanceRelay.sol";
import { MockSpell } from "../mocks/MockSpell.sol";
import { TestHelperOz5WithRevertAssertions } from "./helpers/TestHelperOz5WithRevertAssertions.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PacketBytesHelper } from "./helpers/PacketBytesHelper.sol";
import { MockControlledContractNestedDelivery } from "../mocks/MockControlledContractNestedDelivery.sol";

contract GovernanceControllerOAppTest is TestHelperOz5WithRevertAssertions {
    using OptionsBuilder for bytes;

    uint32 aEid = 1;
    uint32 bEid = 2;

    GovernanceControllerOApp aGov;
    GovernanceControllerOApp bGov;

    MockGovernanceRelay aRelay;
    MockGovernanceRelay bRelay;

    MockControlledContract aControlledContract;
    MockControlledContract bControlledContract;

    address NOT_OWNER = makeAddr("NOT_OWNER");

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        address[] memory sender = setupOApps(type(GovernanceControllerOApp).creationCode, 1, 2);
        aGov = GovernanceControllerOApp(payable(sender[0]));
        bGov = GovernanceControllerOApp(payable(sender[1]));

        aRelay = new MockGovernanceRelay(aGov, addressToBytes32(address(this)), bEid);
        bRelay = new MockGovernanceRelay(bGov, addressToBytes32(address(this)), aEid);

        aControlledContract = new MockControlledContract(address(aRelay));
        bControlledContract = new MockControlledContract(address(bRelay));
    }

    function test_send() public {
        string memory dataBefore = bControlledContract.data();

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // STEP 0: Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        // STEP 1: Sending a message via the _lzSend() method.
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyPackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_send_with_governed_contract_revert() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTest.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(MockGovernanceRelay.TestRevert.selector), "");
    }

    function test_send_with_governed_contract_revert_no_data() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTestNoData.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(GovernanceControllerOApp.GovernanceCallFailed.selector), "");
    }

    function test_send_with_allowlist() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        aGov.enableAllowlist();
        vm.expectRevert(GovernanceControllerOApp.NotAllowlisted.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        aGov.disableAllowlist();
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        aGov.enableAllowlist();
        aGov.addToAllowlist(address(this));
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        aGov.removeFromAllowlist(address(this));
        vm.expectRevert(GovernanceControllerOApp.NotAllowlisted.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));
    }

    function test_allowlist_management() public {
        aGov.enableAllowlist();
        assertEq(aGov.allowlistEnabled(), true);

        aGov.disableAllowlist();
        assertEq(aGov.allowlistEnabled(), false);

        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.enableAllowlist();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        vm.prank(NOT_OWNER);
        aGov.disableAllowlist();
    }

    function test_reentrancy_lz_receive() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockControlledContractNestedDelivery controllerNestedDelivery = new MockControlledContractNestedDelivery(aGov, bGov, address(this));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(controllerNestedDelivery),
            callData: abi.encodeWithSelector(controllerNestedDelivery.deliverNestedPacket.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));

        bytes memory packetOneBytes = hex"01000000000000000100000001000000000000000000000000756e0562323adcda4430d6cb456d9151f605290b000000020000000000000000000000001af7f588a501ea2b5bb3feefa744892aa2cf00e624af70d91a3ee419f51a2d4f11f114a1e0da3511966904b1c7871ff00eee176f01000000020000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e149692a6649fdcc044da968d94202465578a9371c7b100047aba9f80";
        bytes memory packetTwoBytes = hex"01000000000000000200000001000000000000000000000000756e0562323adcda4430d6cb456d9151f605290b000000020000000000000000000000001af7f588a501ea2b5bb3feefa744892aa2cf00e65c4ff3a57f16ea1239276ac9bbd90e50a4a5e5d3d9accc0906f4c26c785ad31c01000000020000000000000000000000007fa9385be102ac3eac297483dd6233d62b3e149692a6649fdcc044da968d94202465578a9371c7b100047aba9f80";
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetOneBytes);
        TestHelperOz5WithRevertAssertions(payable(address(this))).validatePacket(packetTwoBytes);

        (bytes32 guidOne, bytes memory messageOne) = new PacketBytesHelper().decodeGuidAndMessage(packetOneBytes);

        controllerNestedDelivery.setPacketBytes(packetTwoBytes);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        ILayerZeroEndpointV2(endpoints[bEid]).lzReceive(Origin({ srcEid: aEid, sender: addressToBytes32(address(aGov)), nonce: 1 }), address(bGov), guidOne, messageOne, bytes(""));
    }

    function test_send_unauthorized_origin_caller() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(0xdead)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));
    }

    function test_send_raw_bytes() public {
        string memory dataBefore = bControlledContract.data();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        bytes memory messageBytes = GovernanceMessageEVMCodec.encode(message);
        MessagingFee memory fee = aGov.quoteRawBytesAction(messageBytes, options, false);

        aGov.sendRawBytesAction{ value: fee.nativeFee }(messageBytes, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyPackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_sending_garbage_in_origin_caller_reverts() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        bytes32 originCaller = addressToBytes32(address(this));
        bytes32 originCallerWithGarbage = bytes32(abi.encodePacked(bytes12(type(uint96).max), address(this)));
        
        GovernanceMessageEVMCodec.GovernanceMessage memory messageWithGarbage = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: originCallerWithGarbage,
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(messageWithGarbage, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(messageWithGarbage, options, fee, address(this));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            dstEid: bEid,
            originCaller: originCaller,
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        aGov.sendEVMAction{ value: fee.nativeFee }(message, options, fee, address(this));
    }

}
