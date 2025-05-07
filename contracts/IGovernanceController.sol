// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

struct GovernanceOrigin {
    uint32 eid; // LayerZero Endpoint ID
    bytes32 caller; // Caller on the source chain
}

interface IGovernanceController {
    function messageOrigin() external view returns (uint32 eid, bytes32 caller);
}
