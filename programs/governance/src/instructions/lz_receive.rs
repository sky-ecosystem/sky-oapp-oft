// SPDX-License-Identifier: Apache-2.0
//! General purpose governance program.
//!
//! This program is designed to be a generic governance program that can be used to
//! execute arbitrary instructions.
//! The program being governed simply needs to expose admin instructions that can be
//! invoked by a signer account (that's checked by the program's access control logic).
//!
//! If the signer is set to be the "governance" PDA of this program, then the governance
//! instruction is able to invoke the program's admin instructions.
//!
//! The instruction needs to be encoded in the cross chain message payload, with all the
//! accounts. These accounts may be in any order, with two placeholder accounts:
//! - [`OWNER`]: the program will replace this account with the governance PDA
//! - [`PAYER`]: the program will replace this account with the payer account

use crate::error::GovernanceError;
use crate::msg_codec::GovernanceMessage;
use crate::state::CpiAuthorityConfig;
use crate::state::Governance;
use crate::state::Remote;
use crate::{CPI_AUTHORITY_SEED, CPI_AUTHORITY_CONFIG_SEED, GOVERNANCE_SEED, PAYER_PLACEHOLDER, REMOTE_SEED, CPI_AUTHORITY_PLACEHOLDER, id};
use anchor_lang::prelude::*;
use oapp::{
    endpoint::{
        cpi::accounts::Clear, instructions::ClearParams, ConstructCPIContext, ID as ENDPOINT_ID,
    },
    LzReceiveParams,
};
use solana_program::instruction::Instruction;

#[derive(Accounts)]
#[instruction(params: LzReceiveParams)]
pub struct LzReceive<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,

    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,

    #[account(
        seeds = [REMOTE_SEED, &governance.key().to_bytes(), &params.src_eid.to_be_bytes()],
        bump = remote.bump,
        constraint = params.sender == remote.address
    )]
    pub remote: Account<'info, Remote>,

    #[account(
        seeds = [CPI_AUTHORITY_SEED, &governance.key().to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()],
        bump
    )]
    pub cpi_authority: AccountInfo<'info>,

    #[account(
        init_if_needed,
        payer = payer,
        space = CpiAuthorityConfig::SIZE,
        seeds = [CPI_AUTHORITY_CONFIG_SEED, &governance.key().to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()],
        bump
    )]
    pub cpi_authority_config: Account<'info, CpiAuthorityConfig>,

    #[account(executable)]
    pub program: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}

impl<'info> LzReceive<'info> {
    pub fn apply(
        ctx: &mut Context<'_, '_, '_, 'info, Self>,
        params: &LzReceiveParams,
    ) -> Result<()> {
        if ctx.accounts.cpi_authority_config.cpi_authority_bump == 0 {
            let (_authority, cpi_bump) = Pubkey::find_program_address(
                &[CPI_AUTHORITY_SEED, &ctx.accounts.governance.key().to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()], &id()
            );

            if _authority != ctx.accounts.cpi_authority.key() {
                return Err(GovernanceError::CpiAuthorityMismatch.into());
            }
    
            ctx.accounts.cpi_authority_config.cpi_authority_bump = cpi_bump;
        } else if ctx.accounts.cpi_authority_config.cpi_authority_bump != ctx.bumps.cpi_authority {
            return Err(GovernanceError::CpiAuthorityBumpMismatch.into());
        }

        let governance_seed: &[&[u8]] = &[
            GOVERNANCE_SEED,
            &ctx.accounts.governance.id.to_be_bytes(),
            &[ctx.accounts.governance.bump],
        ];

        let cpi_authority_seed: &[&[u8]] = &[   
            CPI_AUTHORITY_SEED,
            &ctx.accounts.governance.key().to_bytes(),
            &GovernanceMessage::decode_origin_caller(&params.message).unwrap(),
            &[ctx.accounts.governance.bump],
        ];

        // the first 9 accounts are for clear()
        let accounts_for_clear = &ctx.remaining_accounts[0..Clear::MIN_ACCOUNTS_LEN];
        let _ = oapp::endpoint_cpi::clear(
            ENDPOINT_ID,
            ctx.accounts.governance.key(),
            accounts_for_clear,
            governance_seed,
            ClearParams {
                receiver: ctx.accounts.governance.key(),
                src_eid: params.src_eid,
                sender: params.sender,
                nonce: params.nonce,
                guid: params.guid,
                message: params.message.clone(),
            },
        )?;
        // Decode governance message from LZ message
        let gov_msg: GovernanceMessage = GovernanceMessage::from_bytes(&params.message)?;
        let mut instruction: Instruction = gov_msg.into();

        // Replace placeholder accounts
        instruction.accounts.iter_mut().for_each(|acc| {
            if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                acc.pubkey = ctx.accounts.cpi_authority.key();
            } else if acc.pubkey == PAYER_PLACEHOLDER {
                acc.pubkey = ctx.accounts.payer.key();
            }
        });

        solana_program::program::invoke_signed(&instruction, &ctx.remaining_accounts[Clear::MIN_ACCOUNTS_LEN..], &[
            cpi_authority_seed,
        ])?;

        Ok(())
    }
}
