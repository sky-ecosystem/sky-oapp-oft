// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/// @notice The known set of governance actions.
enum GovernanceAction {
    UNDEFINED,
    EVM_CALL,
    SOLANA_CALL
}
