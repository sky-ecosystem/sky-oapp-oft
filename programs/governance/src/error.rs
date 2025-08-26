// SPDX-License-Identifier: Apache-2.0
use anchor_lang::prelude::error_code;

#[error_code]
pub enum GovernanceError {
    #[msg("CpiAuthorityDataNotEmpty")]
    CpiAuthorityDataNotEmpty,
    #[msg("CpiAuthorityOwnerNotSystemProgram")]
    CpiAuthorityOwnerNotSystemProgram,
    #[msg("InvalidGovernanceMessage")]
    InvalidGovernanceMessage,
    #[msg("InvalidGovernanceAction")]
    InvalidGovernanceAction,
    #[msg("GovernedProgramIdMismatch")]
    GovernedProgramIdMismatch,
    #[msg("Unauthorized")]
    Unauthorized,
}
