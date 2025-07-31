// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Packet } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20Mock } from "@layerzerolabs/oft-evm/test/mocks/ERC20Mock.sol";
import { ILayerZeroEndpointV2, Origin } from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

import { GovernanceControllerOApp } from "../../contracts/GovernanceControllerOApp.sol";
import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";
import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { MockControlledContract } from "../mocks/MockControlledContract.sol";
import { MockGovernanceRelay } from "../mocks/MockGovernanceRelay.sol";
import { MockSpell } from "../mocks/MockSpell.sol";
import { TestHelperOz5WithRevertAssertions } from "./helpers/TestHelperOz5WithRevertAssertions.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { PacketBytesHelper } from "./helpers/PacketBytesHelper.sol";
import { MockControlledContractNestedDelivery } from "../mocks/MockControlledContractNestedDelivery.sol";
import { MockFundsReceiver } from "../mocks/MockFundsReceiver.sol";

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
    address THIEF = makeAddr("THIEF");

    /// @notice Calls setUp from TestHelper and initializes contract instances for testing.
    function setUp() public virtual override {
        super.setUp();

        // Setup function to initialize 2 Mock Endpoints with Mock MessageLib.
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aGov = new GovernanceControllerOApp(
            endpoints[aEid],
            address(this), // delegate/owner
            false, // whitelistInitialPair
            0, // initialWhitelistedSrcEid
            bytes32(0), // initialWhitelistedOriginCaller
            address(0) // initialWhitelistedGovernedContract
        );

        bGov = new GovernanceControllerOApp(
            endpoints[bEid],
            address(this), // delegate/owner
            false, // whitelistInitialPair
            0, // initialWhitelistedSrcEid
            bytes32(0), // initialWhitelistedOriginCaller
            address(0) // initialWhitelistedGovernedContract
        );

        // Setup peers
        aGov.setPeer(bEid, addressToBytes32(address(bGov)));
        bGov.setPeer(aEid, addressToBytes32(address(aGov)));

        aRelay = new MockGovernanceRelay(aGov, addressToBytes32(address(this)), bEid);
        bRelay = new MockGovernanceRelay(bGov, addressToBytes32(address(this)), aEid);

        aControlledContract = new MockControlledContract(address(aRelay));
        bControlledContract = new MockControlledContract(address(bRelay));

        aGov.addToAllowlist(address(this));

        // Add necessary whitelist entries for the tests to pass
        aGov.updateWhitelist(bEid, addressToBytes32(address(this)), address(aRelay), true);
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(bRelay), true);
    }

    function test_send() public {
        string memory dataBefore = bControlledContract.data();

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // STEP 0: Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        // STEP 1: Sending a message via the _lzSend() method.
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");

        // Asserting that the origin caller and eid are reset after governed contract execution.
        (uint32 originEid, bytes32 originCaller) = aGov.messageOrigin();

        assertEq(originEid, 0);
        assertEq(originCaller, bytes32(0));
    }

    function test_send_with_governed_contract_revert() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTest.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(MockGovernanceRelay.TestRevert.selector), "");
    }

    function test_send_with_governed_contract_revert_no_data() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.revertTestNoData.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(GovernanceControllerOApp.GovernanceCallFailed.selector), "");
    }

    function test_send_with_allowlist() public {
        aGov.removeFromAllowlist(address(this));
        assertEq(aGov.allowlist(address(this)), false);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.NotAllowlisted.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        aGov.addToAllowlist(address(this));
        assertEq(aGov.allowlist(address(this)), true);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        aGov.removeFromAllowlist(address(this));
        assertEq(aGov.allowlist(address(this)), false);
        vm.expectRevert(GovernanceControllerOApp.NotAllowlisted.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_allowlist_management() public {
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.addToAllowlist(address(0x123));

        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.removeFromAllowlist(address(0x123));

        aGov.addToAllowlist(address(0x123));
        assertEq(aGov.allowlist(address(0x123)), true);

        aGov.removeFromAllowlist(address(0x123));
        assertEq(aGov.allowlist(address(0x123)), false);
    }

    function test_whitelist_management() public {
        uint32 srcEid = 123;
        bytes32 originCaller = bytes32(uint256(uint160(address(0x456))));
        address governedContract = address(0x789);

        // Test unauthorized access
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.updateWhitelist(srcEid, originCaller, governedContract, true);

        // Test initial state
        assertEq(aGov.whitelist(srcEid, originCaller, governedContract), false);

        // Test adding to whitelist
        aGov.updateWhitelist(srcEid, originCaller, governedContract, true);
        assertEq(aGov.whitelist(srcEid, originCaller, governedContract), true);

        // Test removing from whitelist
        aGov.updateWhitelist(srcEid, originCaller, governedContract, false);
        assertEq(aGov.whitelist(srcEid, originCaller, governedContract), false);
    }

    function test_batch_whitelist_management() public {
        uint32[] memory srcEids = new uint32[](2);
        bytes32[] memory originCallers = new bytes32[](2);
        address[] memory governedContracts = new address[](2);
        bool[] memory allowed = new bool[](2);

        srcEids[0] = 123;
        srcEids[1] = 124;
        originCallers[0] = bytes32(uint256(uint160(address(0x456))));
        originCallers[1] = bytes32(uint256(uint160(address(0x457))));
        governedContracts[0] = address(0x789);
        governedContracts[1] = address(0x790);
        allowed[0] = true;
        allowed[1] = false;

        // Test unauthorized access
        vm.prank(NOT_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, NOT_OWNER));
        aGov.batchUpdateWhitelist(srcEids, originCallers, governedContracts, allowed);

        // Test batch update
        aGov.batchUpdateWhitelist(srcEids, originCallers, governedContracts, allowed);
        assertEq(aGov.whitelist(srcEids[0], originCallers[0], governedContracts[0]), true);
        assertEq(aGov.whitelist(srcEids[1], originCallers[1], governedContracts[1]), false);

        // Test array length mismatch
        uint32[] memory invalidSrcEids = new uint32[](1);
        invalidSrcEids[0] = 123;
        vm.expectRevert(GovernanceControllerOApp.InvalidWhitelistArrayLengths.selector);
        aGov.batchUpdateWhitelist(invalidSrcEids, originCallers, governedContracts, allowed);

        // Test array length mismatch
        bytes32[] memory invalidOriginCallers = new bytes32[](1);
        invalidOriginCallers[0] = bytes32(uint256(uint160(address(0x456))));
        vm.expectRevert(GovernanceControllerOApp.InvalidWhitelistArrayLengths.selector);
        aGov.batchUpdateWhitelist(srcEids, invalidOriginCallers, governedContracts, allowed);

        // Test array length mismatch
        address[] memory invalidGovernedContracts = new address[](1);
        invalidGovernedContracts[0] = address(0x789);
        vm.expectRevert(GovernanceControllerOApp.InvalidWhitelistArrayLengths.selector);
        aGov.batchUpdateWhitelist(srcEids, originCallers, invalidGovernedContracts, allowed);

        // Test array length mismatch
        bool[] memory invalidAllowed = new bool[](1);
        invalidAllowed[0] = true;
        vm.expectRevert(GovernanceControllerOApp.InvalidWhitelistArrayLengths.selector);
        aGov.batchUpdateWhitelist(srcEids, originCallers, governedContracts, invalidAllowed);
    }

    function test_whitelist_enforcement() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        // Remove from whitelist
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(bRelay), false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Should fail due to whitelist check
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodePacked(GovernanceControllerOApp.NotWhitelisted.selector), "");

        // Add back to whitelist
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(bRelay), true);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        // Should succeed now
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_constructor_initializes_whitelist() public {
        // Test that the constructor properly initializes the whitelist
        bytes32 pauseProxy = addressToBytes32(address(this));
        uint32 initialSrcEid = 999;
        address delegate = address(0x123);

        GovernanceControllerOApp testGov = new GovernanceControllerOApp(
            endpoints[aEid],
            delegate,
            true, // whitelistInitialPair
            initialSrcEid, // initialWhitelistedSrcEid
            pauseProxy, // initialWhitelistedOriginCaller
            address(0x123) // initialWhitelistedGovernedContract
        );

        // Check that the initial whitelist entry was created
        assertEq(testGov.whitelist(initialSrcEid, pauseProxy, delegate), true);
    }

    function test_reentrancy_lz_receive() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockControlledContractNestedDelivery controllerNestedDelivery = new MockControlledContractNestedDelivery(aGov, bGov, address(this));

        // Add whitelist entry for the nested delivery contract
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(controllerNestedDelivery), true);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(controllerNestedDelivery),
            callData: abi.encodeWithSelector(controllerNestedDelivery.deliverNestedPacket.selector)
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        bytes32 packetOneGuid = keccak256(abi.encodePacked(uint64(1), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetOneBytes = abi.encodePacked(
            hex"01000000000000000100000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetOneGuid,
            GovernanceMessageEVMCodec.encode(message)
        );

        bytes32 packetTwoGuid = keccak256(abi.encodePacked(uint64(2), uint32(aEid), addressToBytes32(address(aGov)), uint32(bEid), addressToBytes32(address(bGov))));
        bytes memory packetTwoBytes = abi.encodePacked(
            hex"01000000000000000200000001000000000000000000000000",
            address(aGov),
            hex"00000002000000000000000000000000",
            address(bGov),
            packetTwoGuid,
            GovernanceMessageEVMCodec.encode(message)
        );
        
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
            originCaller: addressToBytes32(address(0xdead)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_send_raw_bytes() public {
        string memory dataBefore = bControlledContract.data();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        bytes memory messageBytes = GovernanceMessageEVMCodec.encode(message);
        MessagingFee memory fee = aGov.quoteRawBytesAction(messageBytes, bEid, options, false);

        aGov.sendRawBytesAction{ value: fee.nativeFee }(messageBytes, bEid, options, fee, address(this));

        // Asserting that the receiving OApps have NOT had data manipulated.
        assertEq(bControlledContract.data(), dataBefore, "shouldn't be changed until lzReceive packet is verified");

        // STEP 2 & 3: Deliver packet to bGov manually.
        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        // Asserting that the data variable has updated in the receiving OApp.
        assertEq(bControlledContract.data(), "test message", "lzReceive data assertion failure");
    }

    function test_sending_garbage_in_origin_caller_reverts() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        bytes32 originCallerWithGarbage = bytes32(abi.encodePacked(bytes12(type(uint96).max), address(this)));
        
        GovernanceMessageEVMCodec.GovernanceMessage memory messageWithGarbage = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: originCallerWithGarbage,
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        MessagingFee memory fee = aGov.quoteEVMAction(messageWithGarbage, bEid, options, false);

        vm.expectRevert(GovernanceControllerOApp.UnauthorizedOriginCaller.selector);
        aGov.sendEVMAction{ value: fee.nativeFee }(messageWithGarbage, bEid, options, fee, address(this));

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: bytes32(abi.encodePacked(bytes12(0), address(this))),
            governedContract: address(bRelay),
            callData: abi.encodeWithSelector(bRelay.relay.selector, address(spell), abi.encodeWithSelector(spell.cast.selector))
        });
        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));
    }

    function test_send_no_calldata_just_value() public {
        MockFundsReceiver fundsReceiver = new MockFundsReceiver();

        // Add whitelist entry for the funds receiver
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(fundsReceiver), true);

        assertEq(address(fundsReceiver).balance, 0);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 1e10);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(fundsReceiver),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));

        assertEq(address(fundsReceiver).balance, 1e10);
    }

    function test_revert_invalid_governed_contract_endpoint() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        // Add whitelist entry for the endpoint (though it should still revert)
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(endpoints[bEid]), true);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(endpoints[bEid]),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodeWithSelector(GovernanceControllerOApp.InvalidGovernedContract.selector, address(endpoints[bEid])), "");
    }

    function test_governed_contract_can_be_zero_address() public {
        address lzToken = ILayerZeroEndpointV2(endpoints[bEid]).lzToken();

        // Add whitelist entry for the lzToken
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(lzToken), true);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(lzToken),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)));
    }

    function test_revert_invalid_governed_contract_lz_token() public {
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(endpoints[bEid]);

        ERC20Mock lzTokenMock = new ERC20Mock("ZRO", "ZRO");
        lzTokenMock.mint(address(this), 10 ether);

        endpoint.setLzToken(address(lzTokenMock));
        assertEq(endpoint.lzToken(), address(lzTokenMock));

        lzTokenMock.approve(address(aGov), 10 ether);

        // Add whitelist entry for the lzToken (though it should still revert)
        bGov.updateWhitelist(aEid, addressToBytes32(address(this)), address(lzTokenMock), true);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            originCaller: addressToBytes32(address(this)),
            governedContract: address(lzTokenMock),
            callData: abi.encodeWithSelector(lzTokenMock.transferFrom.selector, address(this), THIEF, 10 ether)
        });
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodeWithSelector(GovernanceControllerOApp.InvalidGovernedContract.selector, address(lzTokenMock)), "");

        assertEq(lzTokenMock.balanceOf(THIEF), 0);
    }

}
