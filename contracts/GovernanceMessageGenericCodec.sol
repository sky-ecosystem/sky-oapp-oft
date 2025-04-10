// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

library GovernanceMessageGenericCodec {
    uint8 private constant MODULE_OFFSET = 0;
    uint8 private constant ACTION_OFFSET = MODULE_OFFSET + 32;
    uint8 private constant DST_EID_OFFSET = ACTION_OFFSET + 1;

    function dstEid(bytes calldata _msg) internal pure returns (uint32) {
        return uint32(bytes4(_msg[DST_EID_OFFSET:DST_EID_OFFSET+4]));
    }
}