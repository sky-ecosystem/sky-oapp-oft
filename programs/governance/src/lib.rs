mod instructions;
mod state;

pub mod error;
pub mod msg_codec;

use anchor_lang::prelude::*;
use instructions::*;
use oapp::{endpoint_cpi::LzAccount, LzReceiveParams};
use state::*;
use error::*;

declare_id!("EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3");

pub const SOLANA_CHAIN_ID: u32 = 40168;

const LZ_RECEIVE_TYPES_SEED: &[u8] = b"LzReceiveTypes";
const LZ_RECEIVE_ALT_SEED: &[u8] = b"LzReceiveAlt";
const GOVERNANCE_SEED: &[u8] = b"Governance";
const REMOTE_SEED: &[u8] = b"Remote";

pub const OWNER_PLACEHOLDER: Pubkey = sentinel_pubkey(b"owner");
pub const PAYER_PLACEHOLDER: Pubkey = sentinel_pubkey(b"payer");

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

    pub fn lz_receive_types(
        ctx: Context<LzReceiveTypes>,
        params: LzReceiveParams,
    ) -> Result<Vec<LzAccount>> {
        LzReceiveTypes::apply(&ctx, &params)
    }

    pub fn lz_receive_types_with_alt(
        ctx: Context<LzReceiveTypesWithAlt>,
        params: LzReceiveParams,
    ) -> Result<Vec<LzAccountAlt>> {
        LzReceiveTypesWithAlt::apply(&ctx, &params)
    }

    pub fn set_lz_receive_alt(
        mut ctx: Context<SetLzReceiveAlt>,
        params: SetLzReceiveAltParams,
    ) -> Result<()> {
        SetLzReceiveAlt::apply(&mut ctx, &params)
    }

    pub fn send_oft(mut ctx: Context<SendOFT>, params: SendOFTParams) -> Result<()> {
        SendOFT::apply(&mut ctx, &params)
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
