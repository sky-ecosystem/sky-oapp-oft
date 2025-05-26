// SPDX-License-Identifier: Apache-2.0
use crate::*;

#[derive(Accounts)]
pub struct LzReceiveTypesInfo<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,

    #[account(seeds = [LZ_RECEIVE_TYPES_V2_SEED, &governance.key().as_ref()], bump)]
    pub lz_receive_types_accounts: Account<'info, LzReceiveTypesV2Accounts>,
}

impl LzReceiveTypesInfo<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypesInfo>
    ) -> Result<(u8, LzReceiveTypesV2Accounts)> {
        let version: u8 = 2;
        let account = &ctx.accounts.lz_receive_types_accounts;
        Ok((
            version,
            LzReceiveTypesV2Accounts {
                alts: account.alts.clone(),
                accounts: account.accounts.clone(),
            },
        ))
    }
}