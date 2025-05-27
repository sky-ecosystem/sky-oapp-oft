// SPDX-License-Identifier: Apache-2.0
use crate::*;

/// The payload returned from `lz_receive_types_info` 
/// when version == 2.
/// Provides information needed to construct the call to  `lz_receive_types_v2`.
#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct LzReceiveTypesV2Accounts {
    pub accounts: Vec<Pubkey>,
}

#[derive(Accounts)]
pub struct LzReceiveTypesInfo<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,

    #[account(seeds = [LZ_RECEIVE_TYPES_V2_SEED, &governance.key().as_ref()], bump)]
    pub lz_receive_types_account: Account<'info, LzReceiveTypesV2GovernanceAccounts>,
}

impl LzReceiveTypesInfo<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypesInfo>
    ) -> Result<(u8, LzReceiveTypesV2Accounts)> {
        let version: u8 = 2;

        let mut accounts = vec![
            ctx.accounts.lz_receive_types_account.governance,
        ];
        accounts.extend(ctx.accounts.lz_receive_types_account.alts.clone());

        Ok((
            version,
            LzReceiveTypesV2Accounts {
                accounts,
            },
        ))
    }
}