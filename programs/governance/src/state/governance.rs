// SPDX-License-Identifier: Apache-2.0
use crate::*;

#[account]
pub struct Governance {
    pub id: u8,
    pub admin: Pubkey,
    pub bump: u8,
    pub endpoint_program: Pubkey,
}

impl Governance {
    pub const SIZE: usize = 8 + std::mem::size_of::<Self>();
}

/// A generic account reference that can be:
/// - A direct address (`Address`)
/// - An address indexed from an ALT (`AltIndex`)
#[derive(AnchorSerialize, AnchorDeserialize, Clone, InitSpace)]
pub enum AddressOrAltIndex {
    // Directly supplied public key
    Address(Pubkey),         
    // (ALT list index, address index within ALT) 
    AltIndex(u8, u8),        
}

#[account]
#[derive(InitSpace)]
pub struct GovernanceLzReceiveTypesAccounts {
    #[max_len(10)]
    pub alts: Vec<Pubkey>,
    pub bump: u8,
}
