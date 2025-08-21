// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { OAppSender, OAppCore, MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

import { IGovernanceOAppSender, TxParams } from "./interfaces/IGovernanceOAppSender.sol";

/**
 * @title GovernanceOAppSender
 * @dev Cross-chain governance sender contract that handles outbound governance calls
 * @notice This contract manages permissions and sends governance transactions to remote chains via LayerZero
 * @author LayerZero Labs
 */
contract GovernanceOAppSender is OAppSender, OAppOptionsType3, IGovernanceOAppSender {
    /// @dev The message type identifier for sending transactions
    uint16 public constant SEND_TX = 1;

    /// @dev This mapping is used to determine if a sender is allowed to call a specific target on a given dst EID.
    mapping(address srcSender => mapping(uint32 dstEid => mapping(bytes32 dstTarget => bool canCall))) public canCallTarget;

    /**
     * @dev Constructor to initialize the GovernanceOAppSender contract
     * @param _endpoint The LayerZero endpoint address
     * @param _owner The owner address for the OApp
     */
    constructor(address _endpoint, address _owner) OAppCore(_endpoint, _owner) Ownable(_owner) {
        // TODO need to set this thing up to be the owner of itself, AND the delegate
        // TODO MUST set peer to Ethereum before it transfers ownership to itself, because otherwise it cant receive msg. Also means 
        // if ethereum is EVER removed as a peer, it CANT be set back to itself. 
        // TODO potentially DONT allow removing remote peer from the list because it will brick itself
        // TODO what is the initial setup for this? in terms of validTargets, so the app cant brick itself etc.
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external onlyOwner {
        if (canCallTarget[_srcSender][_dstEid][_dstTarget] == _canCall) revert CanCallTargetIdempotent();

        canCallTarget[_srcSender][_dstEid][_dstTarget] = _canCall;
        emit CanCallTargetSet(_srcSender, _dstEid, _dstTarget, _canCall);
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function quoteTx(TxParams calldata _params, bool _payInLzToken) external view returns (MessagingFee memory fee) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_params);

        return _quote(_params.dstEid, message, options, _payInLzToken);
    }

    /**
     * @inheritdoc IGovernanceOAppSender
     */
    function sendTx(
        TxParams calldata _params,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt) {
        if (!canCallTarget[msg.sender][_params.dstEid][_params.dstTarget]) revert InvalidCall();

        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_params);

        msgReceipt = _lzSend(_params.dstEid, message, options, _fee, _refundAddress);

        emit GovernanceCallSent(msgReceipt.guid);
    }

    /**
     * @dev Build the message and options for sending a governance transaction
     * @param _params The transaction parameters
     * @return message The encoded message containing sender, target, and calldata
     * @return options The LayerZero options for the message
     */
    function _buildMsgAndOptions(TxParams calldata _params) internal view returns (bytes memory, bytes memory) {
        // Convert msg.sender to bytes32 for cross-chain compatibility
        bytes32 msgSenderBytes32 = bytes32(uint256(uint160(msg.sender)));

        // Encode the message with sender, target, and calldata
        bytes memory message = abi.encodePacked(msgSenderBytes32, _params.dstTarget, _params.dstCallData);
        bytes memory options = combineOptions(_params.dstEid, SEND_TX, _params.extraOptions);

        return (message, options);
    }
}
