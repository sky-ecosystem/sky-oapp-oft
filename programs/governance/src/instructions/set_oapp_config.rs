use crate::{error::GovernanceError, *};
use oapp::endpoint::instructions::SetDelegateParams;

#[derive(Accounts)]
pub struct SetOAppConfig<'info> {
    pub admin: Signer<'info>,

    #[account(
        mut,
        seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()],
        bump = governance.bump,
        has_one = admin @GovernanceError::Unauthorized
    )]
    pub governance: Account<'info, Governance>,
}

impl SetOAppConfig<'_> {
    pub fn apply(ctx: &mut Context<SetOAppConfig>, params: &SetOAppConfigParams) -> Result<()> {
        match params.clone() {
            SetOAppConfigParams::Admin(admin) => {
                ctx.accounts.governance.admin = admin;
            },
            SetOAppConfigParams::Delegate(delegate) => {
                let seeds: &[&[u8]] =
                    &[GOVERNANCE_SEED, &ctx.accounts.governance.id.to_be_bytes(), &[ctx.accounts.governance.bump]];
                let _ = oapp::endpoint_cpi::set_delegate(
                    ctx.accounts.governance.endpoint_program,
                    ctx.accounts.governance.key(),
                    &ctx.remaining_accounts,
                    seeds,
                    SetDelegateParams { delegate },
                )?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum SetOAppConfigParams {
    Admin(Pubkey),
    Delegate(Pubkey), // OApp delegate for the endpoint
}
