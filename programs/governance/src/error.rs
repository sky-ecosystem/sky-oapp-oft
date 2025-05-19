// SPDX-License-Identifier: Apache-2.0
use anchor_lang::prelude::error_code;

#[error_code]
pub enum GovernanceError {
    #[msg("InvalidGovernanceChain")]
    InvalidGovernanceChain,
    #[msg("InvalidGovernanceMessage")]
    InvalidGovernanceMessage,
    #[msg("InvalidGovernanceModule")]
    InvalidGovernanceModule,
    #[msg("InvalidGovernanceAction")]
    InvalidGovernanceAction,
    #[msg("InvalidInstruction")]
    InvalidInstruction,
    #[msg("Unauthorized")]
    Unauthorized,
}
