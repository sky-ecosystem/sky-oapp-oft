// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

contract MockGovernanceRelay {
    address public immutable messenger;

    error DelegateCallFailed();
    error TestRevert();
    error UnauthorizedMessenger();
    
    constructor(address _messenger) {
        messenger = _messenger;
    }

    modifier onlyAuthorized() {
        if (msg.sender != address(messenger)) {
            revert UnauthorizedMessenger();
        }

        _;
    }

    function relay(address target, bytes calldata targetData) external onlyAuthorized {
        (bool success, bytes memory result) = target.delegatecall(targetData);

        if (!success) {
            if (result.length == 0) revert DelegateCallFailed();
            assembly ("memory-safe") {
                revert(add(32, result), mload(result))
            }
        }
    }

    function revertTest() external pure {
        revert TestRevert();
    }

    function revertTestNoData() external pure {
        revert();
    }
}