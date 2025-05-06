// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { GovernanceMessageEVMCodec } from "./GovernanceMessageEVMCodec.sol";
import { GovernanceMessageGenericCodec } from "./GovernanceMessageGenericCodec.sol";
import { IGovernanceController } from "./IGovernanceController.sol";

contract GovernanceControllerOApp is OApp, OAppOptionsType3, IGovernanceController {
    /// @notice The known set of governance actions.
    enum GovernanceAction {
        UNDEFINED,
        EVM_CALL,
        SOLANA_CALL
    }

    // @notice Msg types that are used to identify the various OApp operations.
    // @dev This can be extended in child contracts for non-default OApp operations
    // @dev These values are used in things like combineOptions() in OAppOptionsType3.sol.
    uint16 public constant SEND = 1;

    // a temporary variable to store the origin caller and expose it to governed contract
    bytes32 public originCaller;

    error InvalidAction(uint8 action);
    error UnauthorizedOriginCaller();

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    // [---- EXTERNAL METHODS ----]

    function sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        return _sendEVMAction(_message, _extraOptions, _fee, _refundAddress);
    }

    function quoteEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _extraOptions);

        return _quote(_message.dstEid, message, options, _payInLzToken);
    }

    // @notice This method can be used when compiling and serializing governance message offchain
    function sendRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory receipt) {
        return _sendRawBytesAction(_message, _extraOptions, _fee, _refundAddress);
    }

    function quoteRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        if (GovernanceMessageGenericCodec.originCaller(_message) != address(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

        return _quote(dstEid, _message, options, _payInLzToken);
    }

    // [---- INTERNAL METHODS ----]

    function _sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _extraOptions);

        msgReceipt = _lzSend(_message.dstEid, message, options, _fee, _refundAddress);
    }

    function _buildMsgAndOptionsEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions
    ) internal view virtual returns (bytes memory message, bytes memory options) {
        if (AddressCast.toAddress(_message.originCaller) != address(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

        message = GovernanceMessageEVMCodec.encode(_message);
        options = combineOptions(_message.dstEid, SEND, _extraOptions);
    }

    function _sendRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        if (GovernanceMessageGenericCodec.originCaller(_message) != address(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

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

        // @dev This is a temporary variable to store the origin caller and expose it to the governed contract.
        originCaller = message.originCaller;

        (bool success, bytes memory returnData) = message.governedContract.call(message.callData);
        if (!success) {
            revert(string(returnData));
        }

        // @dev set back to zero
        originCaller = bytes32(0);
    }
}