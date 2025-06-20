// SPDX-License-Identifier: Apache-2.0
use anchor_lang::prelude::error_code;

#[error_code]
pub enum GovernanceError {
    #[msg("CpiAuthorityDataNotEmpty")]
    CpiAuthorityDataNotEmpty,
    #[msg("CpiAuthorityOwnerNotSystemProgram")]
    CpiAuthorityOwnerNotSystemProgram,
    #[msg("InvalidGovernanceChain")]
    InvalidGovernanceChain,
    #[msg("InvalidGovernanceMessage")]
    InvalidGovernanceMessage,
    #[msg("InvalidGovernanceAction")]
    InvalidGovernanceAction,
    #[msg("Unauthorized")]
    Unauthorized,
    #[msg("UnexpectedExtraData")]
    UnexpectedExtraData,
}
