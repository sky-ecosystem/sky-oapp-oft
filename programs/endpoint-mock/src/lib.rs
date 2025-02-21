pub mod instructions;
pub mod state;

use anchor_lang::prelude::*;
use instructions::*;
use state::*;

declare_id!("G4ZhkcwQousR1Wnqtg9f3yKxcp5CyDn2KvXKbsnskh8M");

pub const OAPP_SEED: &[u8] = b"OApp";

#[program]
pub mod endpoint {
    use super::*;

    pub fn register_oapp(mut ctx: Context<RegisterOApp>, params: RegisterOAppParams) -> Result<()> {
        RegisterOApp::apply(&mut ctx, &params)
    }
}
