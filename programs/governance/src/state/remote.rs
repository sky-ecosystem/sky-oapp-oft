// SPDX-License-Identifier: Apache-2.0
use crate::*;

#[account]
#[derive(InitSpace)]
pub struct Remote {
    pub address: [u8; 32],
    pub bump: u8,
}
