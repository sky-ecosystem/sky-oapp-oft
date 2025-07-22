// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { IGovernanceController } from "./IGovernanceController.sol";
import { GovernanceMessageEVMCodec } from "./GovernanceMessageEVMCodec.sol";
import { GovernanceMessageGenericCodec } from "./GovernanceMessageGenericCodec.sol";

contract GovernanceControllerOApp is OApp, OAppOptionsType3, ReentrancyGuard, IGovernanceController {
    // @notice Msg types that are used to identify the various OApp operations.
    // @dev This can be extended in child contracts for non-default OApp operations
    // @dev These values are used in things like combineOptions() in OAppOptionsType3.sol.
    uint16 public constant SEND = 1;

    address public immutable governedContract;

    error GovernanceCallFailed();
    error NotAllowlisted();

    // allowlist of addresses allowed to send messages
    mapping(address => bool) public allowlist;

    event AllowlistAdded(address indexed _address);
    event AllowlistRemoved(address indexed _address);

    constructor(address _endpoint, address _delegate, address _governedContract) OApp(_endpoint, _delegate) Ownable(_delegate) {
        governedContract = _governedContract;
    }

    modifier onlyAllowlisted() {
        if (!allowlist[msg.sender]) revert NotAllowlisted();
        _;
    }

    // [---- EXTERNAL METHODS ----]

    function sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyAllowlisted returns (MessagingReceipt memory receipt) {
        return _sendEVMAction(_message, _dstEid, _extraOptions, _fee, _refundAddress);
    }

    // @dev This method disregards the allowlist check.
    function quoteEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _dstEid, _extraOptions);

        return _quote(_dstEid, message, options, _payInLzToken);
    }

    // @notice This method can be used when compiling and serializing governance message offchain
    function sendRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyAllowlisted returns (MessagingReceipt memory receipt) {
        return _sendRawBytesAction(_message, _dstEid, _extraOptions, _fee, _refundAddress);
    }

    // @dev This method disregards the allowlist check.
    function quoteRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        bytes memory options = combineOptions(_dstEid, SEND, _extraOptions);

        return _quote(_dstEid, _message, options, _payInLzToken);
    }

    // [---- ALLOWLIST MANAGEMENT ----]
    /**
     * @notice Adds an address to the allowlist.
     * @param _address The address to add to the allowlist.
     */
    function addToAllowlist(address _address) external onlyOwner {
        allowlist[_address] = true;
        emit AllowlistAdded(_address);
    }

    /**
     * @notice Removes an address from the allowlist.
     * @param _address The address to remove from the allowlist.
     */
    function removeFromAllowlist(address _address) external onlyOwner {
        allowlist[_address] = false;
        emit AllowlistRemoved(_address);
    }

    // [---- INTERNAL METHODS ----]

    function _sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _dstEid, _extraOptions);

        msgReceipt = _lzSend(_dstEid, message, options, _fee, _refundAddress);
    }

    function _buildMsgAndOptionsEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions
    ) internal view virtual returns (bytes memory message, bytes memory options) {
        message = GovernanceMessageEVMCodec.encode(_message);
        options = combineOptions(_dstEid, SEND, _extraOptions);
    }

    function _sendRawBytesAction(
        bytes calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        GovernanceMessageGenericCodec.assertValidMessageLength(_message);

        bytes memory options = combineOptions(_dstEid, SEND, _extraOptions);

        msgReceipt = _lzSend(_dstEid, _message, options, _fee, _refundAddress);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Receive business logic
    //
    // Override _lzReceive to decode the incoming bytes
    // The base OAppReceiver.lzReceive ensures:
    //   • Only the LayerZero Endpoint can call this method
    //   • The sender is a registered peer (peers[srcEid] == origin.sender)
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Invoked when EndpointV2.lzReceive is called
    /// @notice Can be called by anyone with any msg.value
    /// message needs to be verified first by the Security Stack
    /// msg.value (if used) should be validated by the governed contract
    /// 
    /// @notice this function is retryable but not replayable
    ///
    /// @dev   origin     Metadata (source chain, sender address, nonce)
    /// @dev   _guid      Global unique ID for tracking this message
    /// @param payload    Encoded bytes of GovernanceMessage
    /// @dev   _executor  Executor address that delivered the message
    /// @dev   _extraData Additional data from the Executor (unused here)
    function _lzReceive(
        Origin calldata /*origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override nonReentrant {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.decode(payload);

        // @dev Governed contract SHOULD validate the msg.value if its used
        (bool success, bytes memory returnData) = governedContract.call{ value: msg.value }(message.callData);
        if (!success) {
            if (returnData.length == 0) revert GovernanceCallFailed();
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }
    }
}