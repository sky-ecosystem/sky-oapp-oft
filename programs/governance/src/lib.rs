// SPDX-License-Identifier: Apache-2.0
mod instructions;
mod state;

pub mod error;
pub mod msg_codec;

use anchor_lang::prelude::*;
use instructions::*;
use solana_program::pubkey;
use state::*;
use solana_helper::program_id_from_env;
use oapp::LzReceiveParams;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "GOVERNANCE_ID",
    "EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3"
)));

pub const EXECUTOR_ID: Pubkey = pubkey!("6doghB248px58JSSwG4qejQ46kFMW4AMj7vzJnWZHNZn");

pub const GOVERNANCE_SEED: &[u8] = b"Governance";
pub const REMOTE_SEED: &[u8] = b"Remote";
pub const CPI_AUTHORITY_SEED: &[u8] = b"CpiAuthority";

pub const CPI_AUTHORITY_PLACEHOLDER: Pubkey = sentinel_pubkey(b"cpi_authority");
pub const PAYER_PLACEHOLDER: Pubkey = sentinel_pubkey(b"payer");
pub const CONTEXT_PLACEHOLDER: Pubkey = sentinel_pubkey(b"context");

#[program]
pub mod governance {
    use super::*;

    pub fn init_governance(
        mut ctx: Context<InitGovernance>,
        params: InitGovernanceParams,
    ) -> Result<()> {
        InitGovernance::apply(&mut ctx, &params)
    }

    pub fn set_remote(mut ctx: Context<SetRemote>, params: SetRemoteParams) -> Result<()> {
        SetRemote::apply(&mut ctx, &params)
    }

    pub fn lz_receive<'info>(
        mut ctx: Context<'_, '_, '_, 'info, LzReceive<'info>>,
        params: LzReceiveParams,
    ) -> Result<()> {
        LzReceive::apply(&mut ctx, &params)
    }

    pub fn lz_receive_types_info(
        ctx: Context<LzReceiveTypesInfo>,
        params: LzReceiveParams,
    ) -> Result<(u8, oapp::lz_receive_types_v2::LzReceiveTypesV2Accounts)> {
        LzReceiveTypesInfo::apply(&ctx, &params)
    }

    pub fn lz_receive_types_v2(
        ctx: Context<LzReceiveTypesV2>,
        params: LzReceiveParams,
    ) -> Result<oapp::lz_receive_types_v2::LzReceiveTypesV2Result> {
        LzReceiveTypesV2::apply(&ctx, &params)
    }

    pub fn set_oapp_config(
        mut ctx: Context<SetOAppConfig>,
        params: SetOAppConfigParams,
    ) -> Result<()> {
        SetOAppConfig::apply(&mut ctx, &params)
    }
}

const fn sentinel_pubkey(input: &[u8]) -> Pubkey {
    let mut output: [u8; 32] = [0; 32];

    let mut i = 0;
    while i < input.len() {
        output[i] = input[i];
        i += 1;
    }

    Pubkey::new_from_array(output)
}
