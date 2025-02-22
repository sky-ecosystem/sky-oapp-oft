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
        bytes memory messageBytes = hex"000000000000000047656e6572616c507572706f7365476f7665726e616e63650200009ce8cbc3c6fe5a0bdf3ecdc2af991d34d8cc08adddcfa74986b275bf8e9510b06aa606ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a900046f776e657200000000000000000000000000000000000000000000000000000001017061796572000000000000000000000000000000000000000000000000000000000106ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9000092db6c10a58bab95316c39ae35a2493a86ab87473e3ae00c6b30f41e41da0b75000000a800000000000000000000000000000000000000000000000000000000000000000200000000000000706179657200000000000000000000000000000000000000000000000000000001010b1c98dc929ff44cc99e87df456973d361f7c001e75d20a7330ff20ff126fc620101340000000000000000000000f01d1f0000000000a50000000000000006ddf6e1d765a193d9cbe146ceeb79ac1cb485ed5f5b37913a8cf5857eff00a9";

        // Set up options with gas limit
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(4000000, 4000000);

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
