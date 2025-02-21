// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import { GovernanceControllerOApp } from "../contracts/GovernanceControllerOApp.sol";
import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract SendRawBytesScript is Script {
    using OptionsBuilder for bytes;

    function run() external {
        // Load private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the GovernanceControllerOApp address from environment
        address governanceControllerAddress = vm.envAddress("GOVERNANCE_CONTROLLER_ADDRESS");
        GovernanceControllerOApp governanceController = GovernanceControllerOApp(governanceControllerAddress);

        // The raw bytes message to send
        bytes memory messageBytes = hex"000000000000000047656e6572616c507572706f7365476f7665726e616e63650200009ce8cbc3c6fe5a0bdf3ecdc2af991d34d8cc08adddcfa74986b275bf8e9510b06aa62c43318f0f99dfd8c0ebc65b0b23cc661fcd1df64af6aef33b7b83eca8e5819700036f776e65720000000000000000000000000000000000000000000000000000000101706179657200000000000000000000000000000000000000000000000000000000012c43318f0f99dfd8c0ebc65b0b23cc661fcd1df64af6aef33b7b83eca8e5819700000008afaf6d1f0d989bed";

        // Set up options with gas limit
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2000000, 0);

        // Quote the fee
        MessagingFee memory fee = governanceController.quoteRawBytesAction(messageBytes, options, false);

        // Send the message
        governanceController.sendRawBytesAction{value: fee.nativeFee}(
            messageBytes,
            options,
            fee,
            msg.sender // refund address
        );

        vm.stopBroadcast();
    }
}
