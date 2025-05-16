// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { GovernanceMessageEVMCodec } from "../../../contracts/GovernanceMessageEVMCodec.sol";

contract MockCodec {
    function decode(bytes calldata _message) external pure returns (GovernanceMessageEVMCodec.GovernanceMessage memory) {
        return GovernanceMessageEVMCodec.decode(_message);
    }
}
