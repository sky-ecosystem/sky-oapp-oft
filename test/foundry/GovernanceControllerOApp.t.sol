// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { GovernanceControllerOApp } from "../../contracts/GovernanceControllerOApp.sol";
import { GovernanceMessageEVMCodec } from "../../contracts/GovernanceMessageEVMCodec.sol";

// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";

// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

// Forge imports
import "forge-std/console.sol";

// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

contract GovernedContract is Ownable {
    error RandomError();

    bool public governanceStuffCalled;

    constructor() Ownable(msg.sender) {}

    function governanceStuff() public onlyOwner {
        governanceStuffCalled = true;
    }

    function governanceRevert() public view onlyOwner {
        revert RandomError();
    }
}

contract MyOAppTest is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;

    GovernanceControllerOApp private aOApp;
    GovernanceControllerOApp private bOApp;
    GovernedContract governedContractB;

    address private userA = address(0x1);
    address private userB = address(0x2);
    uint256 private initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aOApp = GovernanceControllerOApp(_deployOApp(type(GovernanceControllerOApp).creationCode, abi.encode(address(endpoints[aEid]), address(this))));

        bOApp = GovernanceControllerOApp(_deployOApp(type(GovernanceControllerOApp).creationCode, abi.encode(address(endpoints[bEid]), address(this))));

        address[] memory oapps = new address[](2);
        oapps[0] = address(aOApp);
        oapps[1] = address(bOApp);
        this.wireOApps(oapps);

        governedContractB = new GovernedContract();
        governedContractB.transferOwnership(address(bOApp));
    }

    function test_constructor() public view {
        assertEq(aOApp.owner(), address(this));
        assertEq(bOApp.owner(), address(this));

        assertEq(address(aOApp.endpoint()), address(endpoints[aEid]));
        assertEq(address(bOApp.endpoint()), address(endpoints[bEid]));
    }

    function decodeEVMMessageCodec(
        bytes calldata _message
    ) public pure returns (uint8 action, uint32 dstEid, address governanceContract, address governedContract, bytes memory callData) {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = 
            GovernanceMessageEVMCodec.decode(_message);

        action = message.action;
        dstEid = message.dstEid;
        governanceContract = message.governanceContract;
        governedContract = message.governedContract;
        callData = message.callData;
    }

    function test_parse_evm_message() public view {
        bytes memory foo = hex"000000000000000047656e6572616c507572706f7365476f7665726e616e6365010000a869d8e4c2dbdd2e2bd8f1336ea691dbff6952b1a6ebf890982f9310df57d00f659cf4fd87e65aded8d70004beefface";

        (uint8 action, uint32 dstEid, address governanceContract, address governedContract, bytes memory callData) = this.decodeEVMMessageCodec(foo);
        assertEq(action, uint8(GovernanceControllerOApp.GovernanceAction.EVM_CALL));
        assertEq(dstEid, uint32(43113));
        assertEq(governanceContract, address(0xD8E4C2DbDd2e2bd8F1336EA691dBFF6952B1a6eB));
        assertEq(governedContract, address(0xF890982f9310df57d00f659cf4fd87e65adEd8d7));
        assertEq(callData, hex"beefface");
    }

    function test_encode_message() public view {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceControllerOApp.GovernanceAction.EVM_CALL),
            dstEid: uint32(43113),
            governanceContract: address(0xD8E4C2DbDd2e2bd8F1336EA691dBFF6952B1a6eB),
            governedContract: address(0xF890982f9310df57d00f659cf4fd87e65adEd8d7),
            callData: hex"beefface"
        });
        
        bytes memory encoded = GovernanceMessageEVMCodec.encode(message);

        (uint8 action, uint32 dstEid, address governanceContract, address governedContract, bytes memory callData) = this.decodeEVMMessageCodec(encoded);
        assertEq(action, message.action);
        assertEq(dstEid, message.dstEid);
        assertEq(governanceContract, message.governanceContract);
        assertEq(governedContract, message.governedContract);
        assertEq(callData, message.callData);
    }

    function test_governance() public {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.GovernanceMessage({
            action: uint8(GovernanceControllerOApp.GovernanceAction.EVM_CALL),
            dstEid: bEid,
            governanceContract: address(bOApp),
            governedContract: address(governedContractB),
            callData: abi.encodeWithSignature("governanceStuff()")
        });

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        MessagingFee memory fee = aOApp.quoteEVMAction(message, options, false);

        aOApp.sendEVMAction{value: fee.nativeFee}(message, options, fee, address(this));

        verifyPackets(bEid, addressToBytes32(address(bOApp)));

        assertEq(governedContractB.governanceStuffCalled(), true);
    }
}