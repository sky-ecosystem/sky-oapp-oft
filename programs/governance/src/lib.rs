mod instructions;
mod msg_codec;
mod state;

pub mod error;

use anchor_lang::prelude::*;
use instructions::*;
use oapp::{endpoint_cpi::LzAccount, LzReceiveParams};
use state::*;

declare_id!("356rTMX9NQYuLCXcpDa3qqCAq4c9Q56kTnPrCyrRX8K6");

pub const SOLANA_CHAIN_ID: u32 = 40168;

const LZ_RECEIVE_TYPES_SEED: &[u8] = b"LzReceiveTypes";
const GOVERNANCE_SEED: &[u8] = b"Governance";
const REMOTE_SEED: &[u8] = b"Remote";

#[program]
pub mod governance {
    use super::*;

    pub fn init_governance(mut ctx: Context<InitGovernance>, params: InitGovernanceParams) -> Result<()> {
        InitGovernance::apply(&mut ctx, &params)
    }

    pub fn set_remote(mut ctx: Context<SetRemote>, params: SetRemoteParams) -> Result<()> {
        SetRemote::apply(&mut ctx, &params)
    }

    pub fn lz_receive<'info>(
        mut ctx: Context<'_, '_, '_, 'info, LzReceive<'info>>, 
        params: LzReceiveParams
    ) -> Result<()> {
        LzReceive::apply(&mut ctx, &params)
    }

    pub fn lz_receive_types(
        ctx: Context<LzReceiveTypes>,
        params: LzReceiveParams,
    ) -> Result<Vec<LzAccount>> {
        LzReceiveTypes::apply(&ctx, &params)
    }
}