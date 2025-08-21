// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { OApp, Origin, MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OAppOptionsType3 } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";

import { IGovernanceOApp, MessageOrigin, TxParams } from "./interfaces/IGovernanceOApp.sol";

// TODO nat spec and comments
// TODO license?
contract GovernanceOApp is OApp, OAppOptionsType3, ReentrancyGuard, IGovernanceOApp {
    uint16 public constant SEND_TX = 1;

    // a temporary variable to store the origin caller and expose it to target contract
    MessageOrigin private _messageOrigin;

    // @dev This mapping is used to determine if a sender is allowed to call a specific target on a given dst EID.
    mapping(address srcSender => mapping(uint32 dstEid => mapping(bytes32 dstTarget => bool canCall))) public canCallTarget;

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) Ownable(_delegate) {
        // TODO need to set this thing up to be the owner of itself, AND the delegate
        // TODO MUST set peer to Ethereum before it transfers ownership to itself, because otherwise it cant receive msg. Also means 
        // if ethereum is EVER removed as a peer, it CANT be set back to itself. 
        // TODO potentially DONT allow removing remote peer from the list because it will brick itself
        // TODO what is the initial setup for this? in terms of validTargets, so the app cant brick itself etc.
    }

    // =============================== Sender Functions ===============================

    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external onlyOwner {
        if (canCallTarget[_srcSender][_dstEid][_dstTarget] == _canCall) revert CanCallTargetIdempotent();

        canCallTarget[_srcSender][_dstEid][_dstTarget] = _canCall;
        emit CanCallTargetSet(_srcSender, _dstEid, _dstTarget, _canCall);
    }

    function quoteTx(TxParams calldata _params,bool _payInLzToken) external view returns (MessagingFee memory) {
        (bytes memory message, bytes memory options) = _buildMsgAndOptions(_params);

        return _quote(_params.dstEid, message, options, _payInLzToken);
    }

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

    function _buildMsgAndOptions(TxParams calldata _params) internal view returns (bytes memory, bytes memory) {
        // @dev convert msg.sender to bytes32
        bytes32 msgSenderBytes32 = bytes32(uint256(uint160(msg.sender)));

        bytes memory message = abi.encodePacked(msgSenderBytes32, _params.dstTarget, _params.dstCallData);
        bytes memory options = combineOptions(_params.dstEid, SEND_TX, _params.extraOptions);

        return (message, options);
    }

    // =============================== Receiver Functions ===============================

    function messageOrigin() external view returns (MessageOrigin memory) {
        return _messageOrigin;
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override nonReentrant {
        bytes32 srcSender = bytes32(_payload[0:32]);
        // @dev We skip the first 12 bytes when decoding the address because the source sender doesn't know if the
        // destination expects a 20-byte or 32-byte address. To ensure compatibility, the source pads the address
        // to 32 bytes when encoding for the EVM. Here, we extract bytes 44:64 (the last 20 bytes of the 32-byte
        // padded field) as the address.
        address dstTarget = address(uint160(bytes20(_payload[44:64])));
        bytes memory dstCallData = _payload[64:];
    
        // @dev dstTarget NEEDS to validate the MessageOrigin struct to confirm it is a valid caller from the source.
        _messageOrigin = MessageOrigin({ srcEid: _origin.srcEid, srcSender: srcSender });

        // @dev Target contract SHOULD validate the msg.value if it's used.
        (bool success, bytes memory returnData) = dstTarget.call{ value: msg.value }(dstCallData);
        if (!success) {
            if (returnData.length == 0) revert GovernanceCallFailed();
            assembly ("memory-safe") {
                revert(add(32, returnData), mload(returnData))
            }
        }

        // @dev Set MessageOrigin to zero to prevent reuse on subsequent calls.
        _messageOrigin = MessageOrigin({ srcEid: 0, srcSender: bytes32(0) });

        emit GovernanceCallReceived(_guid);
    }
}