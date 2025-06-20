// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { OApp, MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { GovernanceMessageEVMCodec } from "./GovernanceMessageEVMCodec.sol";
import { GovernanceMessageGenericCodec } from "./GovernanceMessageGenericCodec.sol";
import { IGovernanceController, GovernanceOrigin } from "./IGovernanceController.sol";

contract GovernanceControllerOApp is OApp, OAppOptionsType3, IGovernanceController, ReentrancyGuard {
    // @notice Msg types that are used to identify the various OApp operations.
    // @dev This can be extended in child contracts for non-default OApp operations
    // @dev These values are used in things like combineOptions() in OAppOptionsType3.sol.
    uint16 public constant SEND = 1;

    // a temporary variable to store the origin caller and expose it to governed contract
    GovernanceOrigin public messageOrigin;

    error GovernanceCallFailed();
    error UnauthorizedOriginCaller();
    error NotAllowlisted();

    // flag to enable or disable allowlist enforcement; disabled by default
    bool public allowlistEnabled;

    // allowlist of addresses allowed to send messages
    mapping(address => bool) public allowlist;

    event AllowlistAdded(address indexed _address);
    event AllowlistRemoved(address indexed _address);

    event AllowlistEnabled();
    event AllowlistDisabled();

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {}

    modifier onlyAllowlisted() {
        if (allowlistEnabled && !allowlist[msg.sender]) revert NotAllowlisted();
        _;
    }

    // [---- EXTERNAL METHODS ----]

    function sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable onlyAllowlisted returns (MessagingReceipt memory receipt) {
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
    ) external payable onlyAllowlisted returns (MessagingReceipt memory receipt) {
        return _sendRawBytesAction(_message, _extraOptions, _fee, _refundAddress);
    }

    function quoteRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        bool _payInLzToken
    ) external view returns (MessagingFee memory fee) {
        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

        return _quote(dstEid, _message, options, _payInLzToken);
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

    /**
     * @notice Enable enforcement of the allowlist.
     */
    function enableAllowlist() external onlyOwner {
        allowlistEnabled = true;
        emit AllowlistEnabled();
    }

    /**
     * @notice Disable enforcement of the allowlist.
     */
    function disableAllowlist() external onlyOwner {
        allowlistEnabled = false;
        emit AllowlistDisabled();
    }

    // [---- INTERNAL METHODS ----]

    function _sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        if (_message.originCaller != AddressCast.toBytes32(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

        (bytes memory message, bytes memory options) = _buildMsgAndOptionsEVMAction(_message, _extraOptions);

        msgReceipt = _lzSend(_message.dstEid, message, options, _fee, _refundAddress);
    }

    function _buildMsgAndOptionsEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        bytes calldata _extraOptions
    ) internal view virtual returns (bytes memory message, bytes memory options) {
        message = GovernanceMessageEVMCodec.encode(_message);
        options = combineOptions(_message.dstEid, SEND, _extraOptions);
    }

    function _sendRawBytesAction(
        bytes calldata _message,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        if (GovernanceMessageGenericCodec.originCaller(_message) != AddressCast.toBytes32(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

        uint32 dstEid = GovernanceMessageGenericCodec.dstEid(_message);
        bytes memory options = combineOptions(dstEid, SEND, _extraOptions);

        msgReceipt = _lzSend(dstEid, _message, options, _fee, _refundAddress);
    }

    function _lzReceive(
        Origin calldata origin,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override nonReentrant {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.decode(payload);

        // @dev This is a temporary variable to store the origin caller and expose it to the governed contract.
        messageOrigin = GovernanceOrigin({ eid: origin.srcEid, caller: message.originCaller });

        (bool success, bytes memory returnData) = message.governedContract.call(message.callData);
        if (!success) {
            if (returnData.length == 0) revert GovernanceCallFailed();
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }

        // @dev set back to zero
        messageOrigin = GovernanceOrigin({ eid: 0, caller: bytes32(0) });
    }
}