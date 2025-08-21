// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

struct TxParams {
    uint32 dstEid;
    bytes32 dstTarget;
    bytes dstCallData;
    bytes extraOptions;
}

struct MessageOrigin {
    uint32 srcEid;
    bytes32 srcSender;
}

// TODO comments
interface IGovernanceOApp {
    error GovernanceCallFailed();
    error CanCallTargetIdempotent();
    error InvalidCall();

    event GovernanceCallSent(bytes32 indexed guid);
    event CanCallTargetSet(address indexed sender, uint32 indexed dstEid, bytes32 indexed dstTarget, bool canCall);
    event GovernanceCallReceived(bytes32 indexed guid);

    function SEND_TX() external view returns (uint16);
    function messageOrigin() external view returns (MessageOrigin memory);
    function canCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget) external view returns (bool);

    function setCanCallTarget(address _srcSender, uint32 _dstEid, bytes32 _dstTarget, bool _canCall) external;

    function quoteTx(TxParams calldata _params,bool _payInLzToken) external view returns (MessagingFee memory);

    function sendTx(
        TxParams calldata _params,
        MessagingFee calldata _fee,
        address _refundAddress
    ) external payable returns (MessagingReceipt memory msgReceipt);
}