use crate::*;
use anchor_lang::prelude::*;

#[derive(Accounts)]
#[instruction(params: SetRemoteParams)]
pub struct SetRemote<'info> {
    #[account(mut, address = governance.admin)]
    pub admin: Signer<'info>,
    #[account(
        init_if_needed,
        payer = admin,
        space = Remote::SIZE,
        seeds = [REMOTE_SEED, &governance.key().to_bytes(), &params.dst_eid.to_be_bytes()],
        bump
    )]
    pub remote: Account<'info, Remote>,
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,
    pub system_program: Program<'info, System>,
}

impl SetRemote<'_> {
    pub fn apply(ctx: &mut Context<SetRemote>, params: &SetRemoteParams) -> Result<()> {
        ctx.accounts.remote.address = params.remote;
        ctx.accounts.remote.bump = ctx.bumps.remote;
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SetRemoteParams {
    pub id: u8,
    pub dst_eid: u32,
    pub remote: [u8; 32],
}