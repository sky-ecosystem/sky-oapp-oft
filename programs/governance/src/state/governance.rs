// SPDX-License-Identifier: Apache-2.0
use crate::*;

#[account]
#[derive(InitSpace)]
pub struct Governance {
    pub id: u64,
    pub admin: Pubkey,
    pub bump: u8,
}

#[account]
#[derive(InitSpace)]
pub struct GovernanceLzReceiveTypesAccounts {
    #[max_len(10)]
    pub alts: Vec<Pubkey>,
    pub bump: u8,
}
