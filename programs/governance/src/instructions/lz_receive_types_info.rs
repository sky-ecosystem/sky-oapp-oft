// SPDX-License-Identifier: Apache-2.0
use oapp::{
    lz_receive_types_v2::{LzReceiveTypesV2Accounts, LZ_RECEIVE_TYPES_VERSION},
    LZ_RECEIVE_TYPES_SEED,
};

use crate::*;

/// LzReceiveTypesInfo instruction implements the versioning mechanism introduced in V2.
///
/// This instruction addresses the compatibility risk of the original LzReceiveType V1 design,
/// which lacked any formal versioning mechanism. The LzReceiveTypesInfo instruction allows
/// the Executor to determine how to interpret the structure of the data returned by
/// lz_receive_types() for different versions.
///
/// Returns (version, versioned_data):
/// - version: u8 — A protocol-defined version identifier for the LzReceiveType logic and return
///   type
/// - versioned_data: Any — A version-specific structure that the Executor decodes based on the
///   version
///
/// For Version 2, the versioned_data contains LzReceiveTypesV2Accounts which provides information
/// needed to construct the call to lz_receive_types_v2.
#[derive(Accounts)]
pub struct LzReceiveTypesInfo<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,

    /// PDA account containing the versioned data structure for V2
    /// Contains the accounts needed to construct lz_receive_types_v2 instruction
    /// Derived using: seeds = [LZ_RECEIVE_TYPES_SEED, &governance.key().to_bytes()]
    #[account(seeds = [LZ_RECEIVE_TYPES_SEED, &governance.key().to_bytes()], bump = lz_receive_types_accounts.bump)]
    pub lz_receive_types_accounts: Account<'info, GovernanceLzReceiveTypesAccounts>,
}

impl LzReceiveTypesInfo<'_> {
    /// Returns the version and versioned data for LzReceiveTypes
    ///
    /// Version Compatibility:
    /// - Forward Compatibility: Executors must gracefully reject unknown versions
    /// - Backward Compatibility: Version 1 OApps do not implement lz_receive_types_info; Executors
    ///   may fall back to assuming V1 if the version instruction is missing or unimplemented
    ///
    /// For V2, returns:
    /// - version: 2 (u8)
    /// - versioned_data: LzReceiveTypesV2Accounts containing the accounts needed for
    ///   lz_receive_types_v2
    pub fn apply(
        ctx: &Context<LzReceiveTypesInfo>,
        _params: &LzReceiveParams
    ) -> Result<(u8, LzReceiveTypesV2Accounts)> {

        let mut accounts = vec![
            ctx.accounts.governance.key(),
        ];
        accounts.extend(ctx.accounts.lz_receive_types_accounts.alts.clone());

        Ok((
            LZ_RECEIVE_TYPES_VERSION,
            LzReceiveTypesV2Accounts {
                accounts,
            },
        ))
    }
}