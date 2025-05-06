// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

interface IGovernanceController {
    function originCaller() external view returns (bytes32);
}
