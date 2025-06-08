// SPDX-License-Identifier: Apache-2.0
use crate::*;

pub const LZ_RECEIVE_VERSION: u8 = 2;

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

    #[account(seeds = [LZ_RECEIVE_TYPES_SEED, &governance.key().as_ref()], bump = lz_receive_types_account.bump)]
    pub lz_receive_types_account: Account<'info, LzReceiveTypesV2GovernanceAccounts>,
}

impl LzReceiveTypesInfo<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypesInfo>
    ) -> Result<(u8, LzReceiveTypesV2Accounts)> {

        let mut accounts = vec![
            ctx.accounts.governance.key(),
        ];
        accounts.extend(ctx.accounts.lz_receive_types_account.alts.clone());

        Ok((
            LZ_RECEIVE_VERSION,
            LzReceiveTypesV2Accounts {
                accounts,
            },
        ))
    }
}