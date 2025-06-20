use crate::{error::GovernanceError, *};
use oapp::{endpoint::{instructions::SetDelegateParams, ID as ENDPOINT_ID}, LZ_RECEIVE_TYPES_SEED};

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

    #[account(
        mut,
        seeds = [LZ_RECEIVE_TYPES_SEED, &governance.key().to_bytes()],
        bump = lz_receive_types_accounts.bump
    )]
    pub lz_receive_types_accounts: Account<'info, GovernanceLzReceiveTypesAccounts>,
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
                    ENDPOINT_ID,
                    ctx.accounts.governance.key(),
                    &ctx.remaining_accounts,
                    seeds,
                    SetDelegateParams { delegate },
                )?;
            },
            SetOAppConfigParams::LzReceiveAlts(alts) => {
                ctx.accounts.lz_receive_types_accounts.alts = alts;
            }
        }
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub enum SetOAppConfigParams {
    Admin(Pubkey),
    Delegate(Pubkey), // OApp delegate for the endpoint
    LzReceiveAlts(Vec<Pubkey>),
}
