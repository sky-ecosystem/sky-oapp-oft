// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { AddressCast } from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

library GovernanceMessageGenericCodec {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant DST_EID_OFFSET = ACTION_OFFSET + 1;
    uint8 private constant ORIGIN_CALLER_OFFSET = DST_EID_OFFSET + 4;

    function action(bytes calldata _msg) internal pure returns (uint8) {
        return uint8(_msg[ACTION_OFFSET]);
    }

    function dstEid(bytes calldata _msg) internal pure returns (uint32) {
        return uint32(bytes4(_msg[DST_EID_OFFSET:DST_EID_OFFSET+4]));
    }

    function originCaller(bytes calldata _msg) internal pure returns (bytes32) {
        return bytes32(_msg[ORIGIN_CALLER_OFFSET:ORIGIN_CALLER_OFFSET+32]);
    }
}