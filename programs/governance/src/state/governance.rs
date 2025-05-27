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


/// The payload returned from lz_receive_types_info when version == 2.
/// Provides information needed to construct the call to lz_receive_types_v2.
/// Represents the accounts required for LzReceiveTypesV2 operations.
///
/// # Fields
/// - `alts`: A vector of `Pubkey` representing alternative accounts. The maximum allowed length is
///   10, which should be sufficient for most use cases.
/// - `accounts`: A vector of `AddressOrAltIndex` representing either direct addresses or indices
///   into the `alts` vector. The maximum allowed length is 30, accommodating a wide range of
///   account configurations.
///
/// The `alts` field is designed to provide flexibility by allowing up to 10 alternative public
/// keys, which can be referenced in the `accounts` field by index. This structure supports
/// efficient account management and lookup in scenarios where multiple alternative accounts may be
/// involved.
#[account]
#[derive(InitSpace)]
pub struct LzReceiveTypesV2Accounts {
    #[max_len(10)]
    pub alts: Vec<Pubkey>,
    #[max_len(30)]
    pub accounts: Vec<AddressOrAltIndex>,
}
