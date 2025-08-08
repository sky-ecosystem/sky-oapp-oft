// SPDX-License-Identifier: MIT
mod instructions;

pub use endpoint;

use anchor_lang::prelude::*;
use instructions::*;
use solana_helper::program_id_from_env;

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "EXTERNAL_MULTICALL_ID",
    "EiQujD3MpwhznKZn4jSa9J7j6cHd7W9QA213QrPZgpR3"
)));

#[program]
pub mod external_multicall {
    use super::*;

    pub fn execute_multicall<'info>(
        mut ctx: Context<'_, '_, '_, 'info, ExecuteMulticall<'info>>,
        params: ExecuteMulticallParams,
    ) -> Result<()> {
        ExecuteMulticall::apply(&mut ctx, &params)
    }
}
