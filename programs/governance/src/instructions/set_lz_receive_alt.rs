// SPDX-License-Identifier: Apache-2.0
use crate::*;
use anchor_lang::prelude::*;

#[derive(Accounts)]
#[instruction(params: SetLzReceiveAltParams)]
pub struct SetLzReceiveAlt<'info> {
    #[account(mut, address = governance.admin)]
    pub admin: Signer<'info>,
    #[account(
        init_if_needed,
        payer = admin,
        space = LzReceiveAlt::SIZE,
        seeds = [LZ_RECEIVE_ALT_SEED, &governance.key().to_bytes()],
        bump
    )]
    pub lz_receive_alt: Account<'info, LzReceiveAlt>,
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,
    pub system_program: Program<'info, System>,
}

impl SetLzReceiveAlt<'_> {
    pub fn apply(ctx: &mut Context<SetLzReceiveAlt>, params: &SetLzReceiveAltParams) -> Result<()> {
        ctx.accounts.lz_receive_alt.address = params.alt;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetLzReceiveAltParams {
    pub alt: Pubkey,
}
