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

/// LzReceiveTypesAccounts includes accounts that are used in the LzReceiveTypes
/// instruction.
#[account]
pub struct LzReceiveTypesAccounts {
    pub governance: Pubkey,
}

impl LzReceiveTypesAccounts {
    pub const SIZE: usize = 8 + std::mem::size_of::<Self>();
}

#[account]
pub struct LzReceiveAlt {
    pub address: Pubkey,
}

impl LzReceiveAlt {
    pub const SIZE: usize = 8 + std::mem::size_of::<Self>();
}
