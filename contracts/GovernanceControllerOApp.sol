// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { GovernanceMessageEVMCodec } from "./GovernanceMessageEVMCodec.sol";
import { GovernanceMessageGenericCodec } from "./GovernanceMessageGenericCodec.sol";

contract GovernanceControllerOApp is OApp, OAppOptionsType3 {
    /// @notice The known set of governance actions.
    /// @dev As the governance logic is expanded to more runtimes, it's
    ///      important to keep them in sync, at least the newer ones should ensure
    ///      they don't overlap with the existing ones.
    ///
    ///      Existing implementations are not strongly required to be updated
    ///      to be aware of new actions (as they will never need to know the
    ///      action indices higher than the one corresponding to the current
    ///      runtime), but it's good practice.
    ///
    ///      When adding a new runtime, make sure to at least update in the README.md
    enum GovernanceAction {
        UNDEFINED,
        EVM_CALL,
        SOLANA_CALL
    }

    // @notice Msg types that are used to identify the various OApp operations.
    // @dev This can be extended in child contracts for non-default OApp operations
    // @dev These values are used in things like combineOptions() in OAppOptionsType3.sol.
    uint16 public constant SEND = 1;

    error InvalidAction(uint8 action);

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    /**
     * @notice Sends an EVM action
     */
    function sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyOwner returns (MessagingReceipt memory receipt) {
        return _sendEVMAction(_message, _extraOptions, _fee, _refundAddress);
    }

    function quoteEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        // @dev Builds the options and message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _extraOptions);

        // @dev Calculates the LayerZero fee for the send() operation.
        return _quote(_message.dstEid, message, options, _payInLzToken);
    }

    function _sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        // @dev Builds the options and message to quote in the endpoint.
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _extraOptions);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(_message.dstEid, message, options, _fee, _refundAddress);
    }

    function _buildMsgAndOptionsEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions
    ) internal view virtual returns (bytes memory message, bytes memory options) {
        // @dev This generated message has the msg.sender encoded into the payload so the remote knows who the caller is.
        message = GovernanceMessageEVMCodec.encode(_message);
        options = combineOptions(_message.dstEid, SEND, _extraOptions);
    }

    /**
     * @notice Sends a raw bytes action
     */
    function sendRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyOwner returns (MessagingReceipt memory receipt) {
        return _sendRawBytesAction(_message, _extraOptions, _fee, _refundAddress);
    }

    function quoteRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

        // @dev Calculates the LayerZero fee for the send() operation.
        return _quote(dstEid, _message, options, _payInLzToken);
    }

    function _sendRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

        // @dev Sends the message to the LayerZero endpoint and returns the LayerZero msg receipt.
        msgReceipt = _lzSend(dstEid, _message, options, _fee, _refundAddress);
    }

    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.decode(payload);

        if (message.action != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(message.action);
        }

        (bool success, bytes memory returnData) = message.governedContract.call(message.callData);
        if (!success) {
            revert(string(returnData));
        }
    }
}