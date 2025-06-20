// SPDX-License-Identifier: Apache-2.0
use crate::{
    CONTEXT_PLACEHOLDER, CPI_AUTHORITY_SEED, EXECUTOR_ID, GOVERNANCE_SEED, PAYER_PLACEHOLDER, REMOTE_SEED, CPI_AUTHORITY_PLACEHOLDER,
    error::GovernanceError,
    msg_codec::GovernanceMessage,
    state::{Governance, Remote},
};
use anchor_lang::prelude::*;
use anchor_lang::system_program;
use oapp::{
    common::{EXECUTION_CONTEXT_SEED, EXECUTION_CONTEXT_VERSION_1},
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
        seeds = [CPI_AUTHORITY_SEED, &governance.key().to_bytes(), &params.src_eid.to_be_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()],
        bump
    )]
    pub cpi_authority: AccountInfo<'info>,

    #[account(executable)]
    pub program: UncheckedAccount<'info>,
}

impl<'info> LzReceive<'info> {
    pub fn apply(
        ctx: &mut Context<'_, '_, '_, 'info, Self>,
        params: &LzReceiveParams,
    ) -> Result<()> {
        let governance_seed: &[&[u8]] = &[
            GOVERNANCE_SEED,
            &ctx.accounts.governance.id.to_be_bytes(),
            &[ctx.accounts.governance.bump],
        ];

        let cpi_authority_seed: &[&[u8]] = &[   
            CPI_AUTHORITY_SEED,
            &ctx.accounts.governance.key().to_bytes(),
            &params.src_eid.to_be_bytes(),
            &GovernanceMessage::decode_origin_caller(&params.message).unwrap(),
            &[ctx.bumps.cpi_authority],
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

        let (execution_context_addr, _) = Pubkey::find_program_address(
            &[
                EXECUTION_CONTEXT_SEED,
                &ctx.accounts.payer.key.to_bytes(),
                &[EXECUTION_CONTEXT_VERSION_1],
            ],
            &EXECUTOR_ID,
        );

        // Replace placeholder accounts
        instruction.accounts.iter_mut().for_each(|acc| {
            if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                acc.pubkey = ctx.accounts.cpi_authority.key();
            } else if acc.pubkey == PAYER_PLACEHOLDER {
                acc.pubkey = ctx.accounts.payer.key();
            } else if acc.pubkey == CONTEXT_PLACEHOLDER {
                acc.pubkey = execution_context_addr;
            }
        });

        solana_program::program::invoke_signed(&instruction, &ctx.remaining_accounts[Clear::MIN_ACCOUNTS_LEN..], &[
            cpi_authority_seed,
        ])?;

        require!(
            ctx.accounts.cpi_authority.owner.key() == system_program::ID,
            GovernanceError::CpiAuthorityOwnerNotSystemProgram
        );
        require!(ctx.accounts.cpi_authority.data_is_empty(), GovernanceError::CpiAuthorityDataNotEmpty);

        Ok(())
    }
}
