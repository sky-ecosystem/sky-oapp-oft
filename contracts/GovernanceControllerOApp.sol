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
    error NotWhitelisted();
    error InvalidGovernedContract(address _governedContract);
    error InvalidWhitelistArrayLengths();

    // allowlist of addresses allowed to send messages
    mapping(address => bool) public allowlist;

    // whitelist of origin callers allowed to call specific governed contracts
    mapping(uint32 srcEid => mapping(bytes32 originCaller => mapping(address governedContract => bool allowed))) public whitelist;

    event AllowlistAdded(address indexed _address);
    event AllowlistRemoved(address indexed _address);
    event WhitelistUpdated(uint32 indexed srcEid, bytes32 indexed originCaller, address indexed governedContract, bool allowed);

    constructor(
        address _endpoint, 
        address _delegate, 
        bool _whitelistInitialPair,
        uint32 _initialWhitelistedSrcEid,
        bytes32 _initialWhitelistedOriginCaller,
        address _initialWhitelistedGovernedContract
    ) OApp(_endpoint, _delegate) Ownable(_delegate) {
        if (_whitelistInitialPair) {
            // @dev (Optional) Add the initial pair to the whitelist to avoid chicken-and-egg problem
            // if the governance self-governs itself via governance messages
            whitelist[_initialWhitelistedSrcEid][_initialWhitelistedOriginCaller][_initialWhitelistedGovernedContract] = true;
            emit WhitelistUpdated(_initialWhitelistedSrcEid, _initialWhitelistedOriginCaller, _initialWhitelistedGovernedContract, true);
        }
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

    // [---- WHITELIST MANAGEMENT ----]
    /**
     * @notice Updates the whitelist for a specific (srcEid, originCaller, governedContract) combination.
     * @param _srcEid The source endpoint ID.
     * @param _originCaller The origin caller address (as bytes32).
     * @param _governedContract The governed contract address.
     * @param _allowed Whether the combination is allowed.
     */
    function updateWhitelist(
        uint32 _srcEid,
        bytes32 _originCaller,
        address _governedContract,
        bool _allowed
    ) external onlyOwner {
        whitelist[_srcEid][_originCaller][_governedContract] = _allowed;
        emit WhitelistUpdated(_srcEid, _originCaller, _governedContract, _allowed);
    }

    /**
     * @notice Batch updates the whitelist for multiple combinations.
     * @param _srcEids Array of source endpoint IDs.
     * @param _originCallers Array of origin caller addresses (as bytes32).
     * @param _governedContracts Array of governed contract addresses.
     * @param _allowed Array of allowed status for each combination.
     */
    function batchUpdateWhitelist(
        uint32[] calldata _srcEids,
        bytes32[] calldata _originCallers,
        address[] calldata _governedContracts,
        bool[] calldata _allowed
    ) external onlyOwner {
        if (_srcEids.length != _originCallers.length || _originCallers.length != _governedContracts.length || _governedContracts.length != _allowed.length) {
            revert InvalidWhitelistArrayLengths();
        }

        for (uint256 i = 0; i < _srcEids.length; i++) {
            whitelist[_srcEids[i]][_originCallers[i]][_governedContracts[i]] = _allowed[i];
            emit WhitelistUpdated(_srcEids[i], _originCallers[i], _governedContracts[i], _allowed[i]);
        }
    }

    // [---- INTERNAL METHODS ----]

    function _sendEVMAction(
        GovernanceMessageEVMCodec.GovernanceMessage calldata _message,
        uint32 _dstEid,
        bytes calldata _extraOptions,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual returns (MessagingReceipt memory msgReceipt) {
        if (_message.originCaller != AddressCast.toBytes32(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

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

        if (GovernanceMessageGenericCodec.originCaller(_message) != AddressCast.toBytes32(msg.sender)) {
            revert UnauthorizedOriginCaller();
        }

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
        Origin calldata origin,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override nonReentrant {
        GovernanceMessageEVMCodec.GovernanceMessage memory message = GovernanceMessageEVMCodec.decode(payload);

        address lzToken = endpoint.lzToken();
        if (message.governedContract == address(endpoint) || (lzToken != address(0) && message.governedContract == lzToken)) {
            revert InvalidGovernedContract(message.governedContract);
        }

        if (!whitelist[origin.srcEid][message.originCaller][message.governedContract]) {
            revert NotWhitelisted();
        }

        // @dev This is a temporary variable to store the origin caller and expose it to the governed contract.
        messageOrigin = GovernanceOrigin({ eid: origin.srcEid, caller: message.originCaller });

        // @dev Governed contract SHOULD validate the msg.value if its used
        (bool success, bytes memory returnData) = message.governedContract.call{ value: msg.value }(message.callData);
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