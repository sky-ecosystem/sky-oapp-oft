// SPDX-License-Identifier: MIT
pub mod instructions;

use std::{alloc::Layout, mem::size_of, ptr::null_mut};

pub use endpoint;

use anchor_lang::prelude::*;
use instructions::*;
use solana_helper::program_id_from_env;
#[cfg(feature = "custom-heap")]
use solana_program::entrypoint::{HEAP_LENGTH, HEAP_START_ADDRESS};

pub struct BumpAllocator {
    pub start: usize,
    pub len: usize,
}

impl BumpAllocator {
    const RESERVED_MEM: usize = 1 * size_of::<*mut u8>();

    /// Return heap position as of this call
    pub unsafe fn pos(&self) -> usize {
        let pos_ptr = self.start as *mut usize;
        *pos_ptr
    }

    /// Reset heap start cursor to position. 
    /// ### This is very unsafe, use wisely
    pub unsafe fn move_cursor(&self, pos: usize) {
        let pos_ptr = self.start as *mut usize;
        *pos_ptr = pos;
    }
}
unsafe impl std::alloc::GlobalAlloc for BumpAllocator {
    #[inline]
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let pos_ptr = self.start as *mut usize;

        let mut pos = *pos_ptr;
        if pos == 0 {
            // First time, set starting position
            pos = self.start + self.len;
        }
        pos = pos.saturating_sub(layout.size());
        pos &= !(layout.align().wrapping_sub(1));
        if pos < self.start + BumpAllocator::RESERVED_MEM {
            return null_mut();
        }
        *pos_ptr = pos;
        pos as *mut u8
    }
    #[inline]
    unsafe fn dealloc(&self, _: *mut u8, _: Layout) {}
}

#[cfg(feature = "custom-heap")]
#[global_allocator]
static A: BumpAllocator = BumpAllocator {
    start: HEAP_START_ADDRESS as usize,
    len: HEAP_LENGTH,
};

declare_id!(Pubkey::new_from_array(program_id_from_env!(
    "EXTERNAL_MULTICALL_ID",
    "7Ackc8DwwpRvEAZsR12Ru27swgk1ifWuEmHQ3g3Q6tbj"
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
