// SPDX-License-Identifier: Apache-2.0
use crate::*;

#[account]
pub struct Governance {
    pub id: u8,
    pub admin: Pubkey,
    pub bump: u8,
}

impl Governance {
    pub const SIZE: usize = 8 + std::mem::size_of::<Self>();
}

#[account]
#[derive(InitSpace)]
pub struct GovernanceLzReceiveTypesAccounts {
    #[max_len(10)]
    pub alts: Vec<Pubkey>,
    pub bump: u8,
}
