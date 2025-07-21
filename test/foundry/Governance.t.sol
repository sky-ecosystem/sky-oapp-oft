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
            address(this) // delegate/owner
        );

        bGov = new GovernanceControllerOApp(
            endpoints[bEid],
            address(this) // delegate/owner
        );

        // Setup peers
        aGov.setPeer(bEid, addressToBytes32(address(bGov)));
        bGov.setPeer(aEid, addressToBytes32(address(aGov)));

        aRelay = new MockGovernanceRelay(address(aGov));
        bRelay = new MockGovernanceRelay(address(bGov));

        aControlledContract = new MockControlledContract(address(aRelay));
        bControlledContract = new MockControlledContract(address(bRelay));

        aGov.addToAllowlist(address(this));
    }

    function test_send() public {
        string memory dataBefore = bControlledContract.data();

        // Generates 1 lzReceive execution option via the OptionsBuilder library.
        // STEP 0: Estimating message gas fees via the quote function.
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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
    }

    function test_send_with_governed_contract_revert() public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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

    function test_send_raw_bytes() public {
        string memory dataBefore = bControlledContract.data();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        MockSpell spell = new MockSpell(bControlledContract);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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

    function test_send_no_calldata_just_value() public {
        MockFundsReceiver fundsReceiver = new MockFundsReceiver();

        assertEq(address(fundsReceiver).balance, 0);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 1e10);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
            governedContract: address(endpoints[bEid]),
            callData: ""
        });
        MessagingFee memory fee = aGov.quoteEVMAction(message, bEid, options, false);

        aGov.sendEVMAction{ value: fee.nativeFee }(message, bEid, options, fee, address(this));

        verifyAndExecutePackets(bEid, addressToBytes32(address(bGov)), 1, address(0), abi.encodeWithSelector(GovernanceControllerOApp.InvalidGovernedContract.selector, address(endpoints[bEid])), "");
    }

    function test_governed_contract_can_be_zero_address() public {
        address lzToken = ILayerZeroEndpointV2(endpoints[bEid]).lzToken();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(150000, 0);

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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

        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceAction.EVM_CALL),
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
