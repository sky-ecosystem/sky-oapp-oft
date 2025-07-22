// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

library GovernanceMessageGenericCodec {
    uint8 private constant ACTION_OFFSET = 0;

    error InvalidGenericMessageLength();

    function assertValidMessageLength(bytes calldata _msg) internal pure {
        if (_msg.length < ACTION_OFFSET + 1) {
            revert InvalidGenericMessageLength();
        }
    }

    function action(bytes calldata _msg) internal pure returns (uint8) {
        return uint8(_msg[ACTION_OFFSET]);
    }
}