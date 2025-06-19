// SPDX-License-Identifier: Apache-2.0
use crate::*;
use oapp::{endpoint::{instructions::RegisterOAppParams, ID as ENDPOINT_ID}, LZ_RECEIVE_TYPES_SEED};

#[derive(Accounts)]
#[instruction(params: InitGovernanceParams)]
pub struct InitGovernance<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        init,
        payer = payer,
        space = Governance::SIZE,
        seeds = [GOVERNANCE_SEED, &params.id.to_be_bytes()],
        bump
    )]
    pub governance: Account<'info, Governance>,
    #[account(
        init,
        payer = payer,
        space = 8 + GovernanceLzReceiveTypesAccounts::INIT_SPACE,
        seeds = [LZ_RECEIVE_TYPES_SEED, &governance.key().to_bytes()],
        bump
    )]
    pub lz_receive_types_v2_accounts: Account<'info, GovernanceLzReceiveTypesAccounts>,
    pub system_program: Program<'info, System>,
}

impl InitGovernance<'_> {
    pub fn apply(ctx: &mut Context<InitGovernance>, params: &InitGovernanceParams) -> Result<()> {
        ctx.accounts.governance.id = params.id;
        ctx.accounts.governance.admin = params.admin;
        ctx.accounts.governance.bump = ctx.bumps.governance;
        ctx.accounts.governance.endpoint_program = params.endpoint;
        ctx.accounts.lz_receive_types_v2_accounts.alts = params.lz_receive_alts.clone();
        ctx.accounts.lz_receive_types_v2_accounts.bump = ctx.bumps.lz_receive_types_v2_accounts;

        // calling endpoint cpi
        let register_params = RegisterOAppParams {
            delegate: ctx.accounts.governance.admin,
        };
        let seeds: &[&[u8]] = &[
            GOVERNANCE_SEED,
            &[ctx.accounts.governance.id],
            &[ctx.accounts.governance.bump],
        ];
        oapp::endpoint_cpi::register_oapp(
            ENDPOINT_ID,
            ctx.accounts.governance.key(),
            ctx.remaining_accounts,
            seeds,
            register_params,
        )?;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitGovernanceParams {
    pub id: u8,
    pub admin: Pubkey,
    pub endpoint: Pubkey,
    pub lz_receive_alts: Vec<Pubkey>,
}
