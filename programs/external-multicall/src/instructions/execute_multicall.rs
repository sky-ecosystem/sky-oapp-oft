// SPDX-License-Identifier: MIT
use anchor_lang::prelude::*;

use endpoint::{
    cpi::accounts::{InitConfig, InitReceiveLibrary, InitSendLibrary, SetConfig, SetReceiveLibrary, SetSendLibrary}, errors::LayerZeroError, instructions::{InitReceiveLibraryParams, InitSendLibraryParams, SetReceiveLibraryParams, SetSendLibraryParams}, state::{MessageLibInfo, OAppRegistry}, InitConfigParams, SetConfigParams, MESSAGE_LIB_SEED, OAPP_SEED
};
use oft::{instructions::{PeerConfigParam, RateLimitParams, SetPeerConfigParams}, state::RateLimiterType};
use solana_program::{instruction::Instruction, program::invoke, pubkey};
use uln::state::ExecutorConfig;

#[cfg(feature = "custom-heap")]
use crate::A;

#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ExecuteMulticallParams {
    pub oapp: Pubkey,
    pub eid: u32,
    pub peer_address: [u8; 32],
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

    pub send_config: UncheckedAccount<'info>,
    pub receive_config: UncheckedAccount<'info>,
    pub send_library_config: UncheckedAccount<'info>,
    pub receive_library_config: UncheckedAccount<'info>,
    pub oft_store: UncheckedAccount<'info>,
    pub peer: UncheckedAccount<'info>,
    pub endpoint_event_authority: UncheckedAccount<'info>,
    pub uln_event_authority: UncheckedAccount<'info>,
    pub default_send_config: UncheckedAccount<'info>,
    pub default_receive_config: UncheckedAccount<'info>,
    pub nonce: UncheckedAccount<'info>,
    pub pending_inbound_nonce: UncheckedAccount<'info>,

    #[account(executable)]
    pub system_program: Program<'info, System>,

    #[account(executable)]
    pub endpoint_program: UncheckedAccount<'info>,

    #[account(executable)]
    pub message_lib_program: UncheckedAccount<'info>,

    #[account(executable)]
    pub oft_program: UncheckedAccount<'info>,
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
        ).with_remaining_accounts(vec![
            // payer
            ctx.accounts.delegate.to_account_info(),
            // uln settings
            ctx.accounts.message_lib.to_account_info(),
            // send config
            ctx.accounts.send_config.to_account_info(),
            // receive config
            ctx.accounts.receive_config.to_account_info(),
            // system program
            ctx.accounts.system_program.to_account_info(),
        ]);

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

        let set_send_library_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            SetSendLibrary {
                signer: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                send_library_config: ctx.accounts.send_library_config.to_account_info(),
                message_lib_info: Some(ctx.accounts.message_lib_info.to_account_info()),
                program: ctx.accounts.endpoint_program.to_account_info(),
                event_authority: ctx.accounts.endpoint_event_authority.to_account_info(),
            },
        );
        endpoint::cpi::set_send_library(set_send_library_cpi_context, SetSendLibraryParams {
            sender: params.oapp,
            eid: params.eid,
            new_lib: ctx.accounts.message_lib.key(),
        })?;

        let set_receive_library_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            SetReceiveLibrary {
                signer: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                receive_library_config: ctx.accounts.receive_library_config.to_account_info(),
                message_lib_info: Some(ctx.accounts.message_lib_info.to_account_info()),
                program: ctx.accounts.endpoint_program.to_account_info(),
                event_authority: ctx.accounts.endpoint_event_authority.to_account_info(),
            },
        );
        endpoint::cpi::set_receive_library(set_receive_library_cpi_context, SetReceiveLibraryParams {
            receiver: params.oapp,
            eid: params.eid,
            grace_period: 0,
            new_lib: ctx.accounts.message_lib.key(),
        })?;

        let uln_config_bytes = vec![1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 51, 205, 185, 251, 86, 210, 138, 47, 2, 140, 187, 54, 194, 84, 167, 213, 76, 146, 240, 65, 155, 83, 228, 77, 220, 192, 165, 195, 115, 248, 84, 242, 0, 0, 0, 0];
        
        let endpoint_set_config_remaining_accounts = vec![
            ctx.accounts.message_lib.to_account_info(),
            ctx.accounts.send_config.to_account_info(),
            ctx.accounts.receive_config.to_account_info(),
            ctx.accounts.default_send_config.to_account_info(),
            ctx.accounts.default_receive_config.to_account_info(),
            ctx.accounts.uln_event_authority.to_account_info(),
            ctx.accounts.message_lib_program.to_account_info(),
        ];

        let set_send_config_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            SetConfig {
                signer: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                message_lib_info: ctx.accounts.message_lib_info.to_account_info(),
                message_lib: ctx.accounts.message_lib.to_account_info(),
                message_lib_program: ctx.accounts.message_lib_program.to_account_info(),
            },
        ).with_remaining_accounts(endpoint_set_config_remaining_accounts.clone());
        endpoint::cpi::set_config(set_send_config_cpi_context, SetConfigParams {
            oapp: params.oapp,
            eid: params.eid,
            config_type: 2, // ULN_CONFIG_TYPE_SEND_ULN
            config: uln_config_bytes.clone(),
        })?;

        let set_receive_config_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            SetConfig {
                signer: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                message_lib_info: ctx.accounts.message_lib_info.to_account_info(),
                message_lib: ctx.accounts.message_lib.to_account_info(),
                message_lib_program: ctx.accounts.message_lib_program.to_account_info(),
            },
        ).with_remaining_accounts(endpoint_set_config_remaining_accounts.clone());
        endpoint::cpi::set_config(set_receive_config_cpi_context, SetConfigParams {
            oapp: params.oapp,
            eid: params.eid,
            config_type: 3, // ULN_CONFIG_TYPE_RECEIVE_ULN
            config: uln_config_bytes.clone(),
        })?;

        let set_executor_config_cpi_context = CpiContext::new(
            ctx.accounts.endpoint_program.to_account_info(),
            SetConfig {
                signer: ctx.accounts.delegate.to_account_info(),
                oapp_registry: ctx.accounts.oapp_registry.to_account_info(),
                message_lib_info: ctx.accounts.message_lib_info.to_account_info(),
                message_lib: ctx.accounts.message_lib.to_account_info(),
                message_lib_program: ctx.accounts.message_lib_program.to_account_info(),
            },
        ).with_remaining_accounts(endpoint_set_config_remaining_accounts);

        let mut executor_config_bytes = Vec::new();
        let executor_config = ExecutorConfig {
            max_message_size: 10000,
            executor: pubkey!("AwrbHeCyniXaQhiJZkLhgWdUCteeWSGaSN1sTfLiY7xK"),
        };

        executor_config.serialize(&mut executor_config_bytes).unwrap();

        endpoint::cpi::set_config(set_executor_config_cpi_context, SetConfigParams {
            oapp: params.oapp,
            eid: params.eid,
            config_type: 1, // ULN_CONFIG_TYPE_EXECUTOR
            config: executor_config_bytes,
        })?;

        Self::init_nonce(ctx, &InitNonceParams {
            local_oapp: params.oapp,
            remote_eid: params.eid,
            remote_oapp: params.peer_address,
        })?;

        Self::set_peer_config(ctx, &SetPeerConfigParams {
            remote_eid: params.eid,
            config: PeerConfigParam::InboundRateLimit(Some(RateLimitParams {
                refill_per_second: Some(1_000),
                capacity: Some(1_000_000_000),
                rate_limiter_type: Some(RateLimiterType::Net),
            })),
        })?;

        Self::set_peer_config(ctx, &SetPeerConfigParams {
            remote_eid: params.eid,
            config: PeerConfigParam::OutboundRateLimit(Some(RateLimitParams {
                refill_per_second: Some(1_000),
                capacity: Some(1_000_000_000),
                rate_limiter_type: Some(RateLimiterType::Net),
            })),
        })?;

        Self::set_peer_config(ctx, &SetPeerConfigParams {
            remote_eid: params.eid,
            config: PeerConfigParam::PeerAddress(params.peer_address),
        })?;

        Self::set_peer_config(ctx, &SetPeerConfigParams {
            remote_eid: params.eid,
            config: PeerConfigParam::EnforcedOptions {
                send: vec![0, 3, 1, 0, 17, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 56, 128], // lzReceive gas = 80,000
                send_and_call: vec![0, 3], // empty options
            },
        })?;

        Ok(())
    }

    fn set_peer_config(ctx: &mut Context<'_, '_, '_, 'info, Self>, params: &SetPeerConfigParams) -> Result<()> {
        // manually moving heap cursor to avoid memory error
        #[cfg(feature = "custom-heap")]
        let heap_start = unsafe { A.pos() };

        let account_metas: Vec<AccountMeta> = vec![
            AccountMeta::new(ctx.accounts.delegate.key(), true),
            AccountMeta::new(ctx.accounts.peer.key(), false),
            AccountMeta::new_readonly(ctx.accounts.oft_store.key(), false),
            AccountMeta::new_readonly(ctx.accounts.system_program.key(), false),
        ];

        let account_infos: Vec<AccountInfo> = vec![
            ctx.accounts.delegate.to_account_info(),
            ctx.accounts.peer.to_account_info(),
            ctx.accounts.oft_store.to_account_info(),
            ctx.accounts.system_program.to_account_info(),            
        ];

        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_peer_config");
        instruction_data.extend_from_slice(&discriminator);

        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetPeerConfigParams");

        let instruction = Instruction {
            program_id: ctx.accounts.oft_program.key(),
            accounts: account_metas,
            data: instruction_data,
        };

        invoke(&instruction, &account_infos)?;

        #[cfg(feature = "custom-heap")]
        unsafe { A.move_cursor(heap_start); }

        Ok(())
    }

    fn init_nonce(ctx: &mut Context<'_, '_, '_, 'info, Self>, params: &InitNonceParams) -> Result<()> {
        let account_metas: Vec<AccountMeta> = vec![
           AccountMeta::new(ctx.accounts.delegate.key(), true),
           AccountMeta::new_readonly(ctx.accounts.oapp_registry.key(), false),
           AccountMeta::new(ctx.accounts.nonce.key(), false),
           AccountMeta::new(ctx.accounts.pending_inbound_nonce.key(), false),
           AccountMeta::new_readonly(ctx.accounts.system_program.key(), false),
       ];

       let account_infos: Vec<AccountInfo> = vec![
           ctx.accounts.delegate.to_account_info(),
           ctx.accounts.oapp_registry.to_account_info(),
           ctx.accounts.nonce.to_account_info(),
           ctx.accounts.pending_inbound_nonce.to_account_info(),
           ctx.accounts.system_program.to_account_info(),            
       ];

       let mut instruction_data = Vec::new();
       let discriminator = sighash("global", "init_nonce");
       instruction_data.extend_from_slice(&discriminator);

       borsh::BorshSerialize::serialize(&params, &mut instruction_data)
           .expect("Failed to serialize InitNonceParams");

       let instruction = Instruction {
           program_id: ctx.accounts.endpoint_program.key(),
           accounts: account_metas,
           data: instruction_data,
       };

       invoke(&instruction, &account_infos)?;

       Ok(())
   }
}

pub fn sighash(namespace: &str, name: &str) -> [u8; 8] {
    let preimage = format!("{}:{}", namespace, name);

    let mut sighash = [0u8; 8];
    sighash.copy_from_slice(
        &anchor_lang::solana_program::hash::hash(preimage.as_bytes()).to_bytes()[..8],
    );
    sighash
}

// redeclared because original InitNonceParams has private fields
#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitNonceParams {
    pub local_oapp: Pubkey, // the PDA of the OApp
    pub remote_eid: u32,
    pub remote_oapp: [u8; 32],
}
