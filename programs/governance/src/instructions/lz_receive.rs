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

        // the first 8 accounts are for clear()
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

        let message = GovernanceMessage::from_bytes(&params.message)?;

        let mut remaining_accounts_read_index = Clear::MIN_ACCOUNTS_LEN;
        for mut instruction in message.instructions.into_iter().map(|ix| Instruction::from(ix.clone())) {
            let cpi_accounts = &ctx.remaining_accounts[remaining_accounts_read_index + 1..remaining_accounts_read_index + 1 + instruction.accounts.len()];
            Self::execute_instruction(ctx, &mut instruction, params.src_eid, &message.origin_caller, &ctx.remaining_accounts[remaining_accounts_read_index], cpi_accounts)?;
            remaining_accounts_read_index += 1 + instruction.accounts.len();
        }

        require!(
            ctx.accounts.cpi_authority.owner.key() == system_program::ID,
            GovernanceError::CpiAuthorityOwnerNotSystemProgram
        );
        require!(ctx.accounts.cpi_authority.data_is_empty(), GovernanceError::CpiAuthorityDataNotEmpty);
       
        Ok(())
    }

    pub fn execute_instruction(
        ctx: &mut Context<'_, '_, '_, 'info, Self>,
        instruction: &mut Instruction,
        src_eid: u32,
        origin_caller: &[u8; 32],
        program_account: &AccountInfo<'info>,
        cpi_accounts: &[AccountInfo<'info>],
    ) -> Result<()> {
        // Assert supplied program id matches the governed program id from the message
        require!(
            instruction.program_id == program_account.key(),
            GovernanceError::GovernedProgramIdMismatch
        );

        // Replace placeholder accounts
        instruction.accounts.iter_mut().for_each(|acc| {
            if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                acc.pubkey = ctx.accounts.cpi_authority.key();
            } else if acc.pubkey == PAYER_PLACEHOLDER {
                acc.pubkey = ctx.accounts.payer.key();
            } else if acc.pubkey == CONTEXT_PLACEHOLDER {
                let (execution_context_addr, _) = Pubkey::find_program_address(
                    &[
                        EXECUTION_CONTEXT_SEED,
                        &ctx.accounts.payer.key.to_bytes(),
                        &[EXECUTION_CONTEXT_VERSION_1],
                    ],
                    &EXECUTOR_ID,
                );
                acc.pubkey = execution_context_addr;
            }
        });

        solana_program::program::invoke_signed(&instruction, cpi_accounts, &[
            &[
                CPI_AUTHORITY_SEED,
                &ctx.accounts.governance.key().to_bytes(),
                &src_eid.to_be_bytes(),
                origin_caller,
                &[ctx.bumps.cpi_authority],
            ]
        ])?;
        Ok(())
    }
}
