// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { MessagingFee } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";

import { GovernanceMessageEVMCodec } from "./GovernanceMessageEVMCodec.sol";

/// @notice The known set of governance actions.
enum GovernanceAction {
    UNDEFINED,
    EVM_CALL,
    SOLANA_CALL
}

interface IGovernanceController {
    function sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt);

    function quoteEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);

    function sendRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt);

    function quoteRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee);
}