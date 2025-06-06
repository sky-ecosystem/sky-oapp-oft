// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { GovernanceAction } from "./IGovernanceController.sol";

library GovernanceMessageEVMCodec {
    // "GeneralPurposeGovernance" (right padded)
    // Solidity right-pads when converting a string to bytes32, so it works better on EVMs
    bytes32 public constant MODULE = 0x47656E6572616C507572706F7365476F7665726E616E63650000000000000000;

    uint8 private constant MODULE_OFFSET = 0;
    uint8 private constant ACTION_OFFSET = MODULE_OFFSET + 32;
    uint8 private constant DST_EID_OFFSET = ACTION_OFFSET + 1;
    uint8 private constant ORIGIN_CALLER_OFFSET = DST_EID_OFFSET + 4;
    uint8 private constant GOVERNED_CONTRACT_OFFSET = ORIGIN_CALLER_OFFSET + 32;
    uint8 private constant CALLDATA_LENGTH_OFFSET = GOVERNED_CONTRACT_OFFSET + 20;
    uint8 private constant CALLDATA_OFFSET = CALLDATA_LENGTH_OFFSET + 2;

    /*
     * @dev General purpose governance message to call arbitrary methods on a governed EVM smart contract.
     *      The wire format for this message is:
     *      - MODULE - 32 bytes
     *      - action - 1 byte
     *      - dstEid - 4 bytes
     *      - originCaller - 32 bytes
     *      - governedContract - 20 bytes
     *      - callDataLength - 2 bytes
     *      - callData - `callDataLength` bytes
     */
    struct GovernanceMessage {
        uint8 action;
        uint32 dstEid;
        bytes32 originCaller;
        address governedContract;
        bytes callData;
    }

    error InvalidAction(uint8 action);
    error InvalidMessageLength();
    error InvalidModule();
    error InvalidCallDataLength();
    error PayloadTooLong(uint256 length);

    function encode(GovernanceMessage memory _message) internal pure returns (bytes memory encoded) {
        if (_message.action != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(_message.action);
        }

        if (_message.callData.length > type(uint16).max) {
            revert PayloadTooLong(_message.callData.length);
        }

        uint16 callDataLength = uint16(_message.callData.length);

        return abi.encodePacked(
            MODULE,
            _message.action,
            _message.dstEid,
            _message.originCaller,
            _message.governedContract,
            callDataLength,
            _message.callData
        );
    }

    function decode(bytes calldata _msg) internal pure returns (GovernanceMessage memory message) {
        if (_msg.length < CALLDATA_OFFSET) revert InvalidMessageLength();
        if (bytes32(_msg[MODULE_OFFSET:ACTION_OFFSET]) != MODULE) revert InvalidModule();
        if (uint8(_msg[ACTION_OFFSET]) != uint8(GovernanceAction.EVM_CALL)) {
            revert InvalidAction(uint8(_msg[ACTION_OFFSET]));
        }
        
        message.action = uint8(_msg[ACTION_OFFSET]);
        message.dstEid = uint32(bytes4(_msg[DST_EID_OFFSET:ORIGIN_CALLER_OFFSET]));
        message.originCaller = bytes32(_msg[ORIGIN_CALLER_OFFSET:GOVERNED_CONTRACT_OFFSET]);
        message.governedContract = address(uint160(bytes20(_msg[GOVERNED_CONTRACT_OFFSET:CALLDATA_LENGTH_OFFSET])));
        uint16 callDataLength = uint16(bytes2(_msg[CALLDATA_LENGTH_OFFSET:CALLDATA_OFFSET]));

        if (_msg.length != CALLDATA_OFFSET + callDataLength) revert InvalidCallDataLength();
        
        message.callData = _msg[CALLDATA_OFFSET:];
    }
}