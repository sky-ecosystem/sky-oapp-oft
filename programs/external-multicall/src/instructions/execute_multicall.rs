// SPDX-License-Identifier: MIT
use anchor_lang::prelude::*;

use endpoint::{
    cpi::accounts::{InitConfig, InitReceiveLibrary, InitSendLibrary},
    errors::LayerZeroError,
    instructions::{InitReceiveLibraryParams, InitSendLibraryParams},
    state::{MessageLibInfo, OAppRegistry, ReceiveLibraryConfig, SendLibraryConfig},
    InitConfigParams,
    MESSAGE_LIB_SEED,
    OAPP_SEED,
    RECEIVE_LIBRARY_CONFIG_SEED,
    SEND_LIBRARY_CONFIG_SEED
};

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ExecuteMulticallParams {
    pub oapp: Pubkey,
    pub eid: u32,
}

#[derive(Accounts)]
#[instruction(params: ExecuteMulticallParams)]
pub struct ExecuteMulticall<'info> {
    pub delegate: Signer<'info>,

    #[account(
        seeds = [OAPP_SEED, params.oapp.as_ref()],
        bump = oapp_registry.bump,
        has_one = delegate,
        seeds::program = endpoint_program
    )]
    pub oapp_registry: Account<'info, OAppRegistry>,
    /// The PDA signer to the message lib when the endpoint calls the message lib program.
    #[account(
        seeds = [MESSAGE_LIB_SEED, message_lib.key.as_ref()],
        bump = message_lib_info.bump,
        constraint = !message_lib_info.to_account_info().is_writable @LayerZeroError::ReadOnlyAccount,
        seeds::program = endpoint_program
    )]
    pub message_lib_info: Account<'info, MessageLibInfo>,
    /// the pda of the message_lib_program
    #[account(
        seeds = [MESSAGE_LIB_SEED],
        bump = message_lib_info.message_lib_bump,
        seeds::program = message_lib_program
    )]
    pub message_lib: AccountInfo<'info>,

    #[account(
        seeds = [SEND_LIBRARY_CONFIG_SEED, &params.oapp.to_bytes(), &params.eid.to_be_bytes()],
        bump = send_library_config.bump,
        seeds::program = endpoint_program
    )]
    pub send_library_config: Account<'info, SendLibraryConfig>,

    #[account(
        seeds = [RECEIVE_LIBRARY_CONFIG_SEED, &params.oapp.to_bytes(), &params.eid.to_be_bytes()],
        bump = receive_library_config.bump,
        seeds::program = endpoint_program
    )]
    pub receive_library_config: Account<'info, ReceiveLibraryConfig>,

    #[account(executable)]
    pub system_program: Program<'info, System>,

    #[account(executable)]
    pub endpoint_program: UncheckedAccount<'info>,

    #[account(executable)]
    pub message_lib_program: UncheckedAccount<'info>,
}

impl<'info> ExecuteMulticall<'info> {
    pub fn apply(
        ctx: &mut Context<'_, '_, '_, 'info, Self>,
        params: &ExecuteMulticallParams,
    ) -> Result<()> {
        let init_config_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            InitConfig {
                delegate: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                message_lib_info: ctx.accounts.message_lib_info.to_account_info(),
                message_lib: ctx.accounts.message_lib.to_account_info(),
                message_lib_program: ctx.accounts.message_lib_program.to_account_info(),
            },
        );

        endpoint::cpi::init_config(init_config_cpi_context, InitConfigParams {
            oapp: params.oapp,
            eid: params.eid
        })?;

        let init_send_library_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            InitSendLibrary {
                delegate: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                send_library_config: ctx.accounts.send_library_config.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
            },
        );
        endpoint::cpi::init_send_library(init_send_library_cpi_context, InitSendLibraryParams {
            sender: params.oapp,
            eid: params.eid,
        })?;

        let init_receive_library_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            InitReceiveLibrary {
                delegate: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                receive_library_config: ctx.accounts.receive_library_config.to_account_info(),
                system_program: ctx.accounts.system_program.to_account_info(),
            },
        );
        endpoint::cpi::init_receive_library(init_receive_library_cpi_context, InitReceiveLibraryParams {
            receiver: params.oapp,
            eid: params.eid,
        })?;

        Ok(())
    }
}
