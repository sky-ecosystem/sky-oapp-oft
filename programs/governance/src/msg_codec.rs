// SPDX-License-Identifier: Apache-2.0
use crate::{error::GovernanceError, primitive_types_helper};
use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;
use solana_program::pubkey::Pubkey;
use std::io::{self, Read, Write};

/// General purpose governance message to call arbitrary instructions on a governed programs.
/// Batch governance message wire format for multiple instructions:
/// | field              |                     size (bytes) | description                             |
/// |--------------------|-----------------------------------|----------------------------------------|
/// | ACTION             |                                1 | Governance action identifier            |
/// | ORIGIN_CALLER      |                               32 | Origin caller address as bytes32        |
/// | instructions_count |                                2 | Number of instructions in batch         |
/// | instructions       |                         variable | Array of instruction bodies             |
///
/// Each instruction body format:
/// | field           |                     size (bytes) | description                             |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | program_id      |                               32 | Program ID of the program to be invoked |
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data_length     |                                4 | Length of instruction data              |
/// | data            |                  `data_length`   | Data to be passed to the program        |
///

/// Batch governance message for executing multiple instructions atomically
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
    pub origin_caller: [u8; 32],
    pub instructions: Vec<GovernanceInstruction>,
}

/// Individual instruction within a batch message
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceInstruction {
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl GovernanceMessage {
    pub fn from_bytes(message: &[u8]) -> Result<Self> {
        Self::decode(&mut message.as_ref())
            .map_err(|_| error!(GovernanceError::InvalidGovernanceMessage))
    }

    /// Decode a full governance batch message (header + body).
    pub fn decode(reader: &mut &[u8]) -> io::Result<Self> {
        let action: u8 = primitive_types_helper::read_u8(reader)?;
        if action != GovernanceAction::SolanaCall as u8 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                GovernanceError::InvalidGovernanceAction.to_string(),
            ));
        }

        let origin_caller = primitive_types_helper::read_bytes32(reader)?;
        let instructions_count = primitive_types_helper::read_u16(reader)?;
        let mut instructions = Vec::with_capacity(instructions_count as usize);

        for _ in 0..instructions_count {
            let program_id = primitive_types_helper::read_pubkey(reader)?;
            let accounts_len = primitive_types_helper::read_u16(reader)?;
            let mut accounts = Vec::with_capacity(accounts_len as usize);

            for _ in 0..accounts_len {
                let pubkey = primitive_types_helper::read_pubkey(reader)?;
                let is_signer = primitive_types_helper::read_u8(reader)? != 0;
                let is_writable = primitive_types_helper::read_u8(reader)? != 0;
                accounts.push(Acc {
                    pubkey,
                    is_signer,
                    is_writable,
                });
            }

            let data_len = primitive_types_helper::read_u32(reader)?;
            let mut data = vec![0u8; data_len as usize];
            reader.read_exact(&mut data)?;

            instructions.push(GovernanceInstruction {
                program_id,
                accounts,
                data,
            });
        }

        Ok(Self {
            origin_caller,
            instructions,
        })
    }

    /// Encode a full governance batch message (header + body).
    pub fn encode<W: Write>(&self, writer: &mut W) -> io::Result<()> {
        primitive_types_helper::write_u8(writer, GovernanceAction::SolanaCall as u8)?;
        primitive_types_helper::write_bytes32(writer, &self.origin_caller)?;
        primitive_types_helper::write_u16(writer, self.instructions.len() as u16)?;

        for instruction in &self.instructions {
            primitive_types_helper::write_pubkey(writer, &instruction.program_id)?;
            primitive_types_helper::write_u16(writer, instruction.accounts.len() as u16)?;

            for acc in &instruction.accounts {
                primitive_types_helper::write_pubkey(writer, &acc.pubkey)?;
                primitive_types_helper::write_u8(writer, acc.is_signer as u8)?;
                primitive_types_helper::write_u8(writer, acc.is_writable as u8)?;
            }

            primitive_types_helper::write_u32(writer, instruction.data.len() as u32)?;
            writer.write_all(&instruction.data)?;
        }

        Ok(())
    }

    /// Decodes ONLY the origin caller from the batch message.
    pub fn decode_origin_caller(message: &[u8]) -> Result<[u8; 32]> {
        let origin_caller_start = 1;
        let origin_caller_end = origin_caller_start + 32;

        if message.len() < origin_caller_end {
            return Err(error!(GovernanceError::InvalidGovernanceMessage));
        }
        
        let mut origin_caller = [0u8; 32];
        origin_caller.copy_from_slice(&message[origin_caller_start..origin_caller_end]);
        Ok(origin_caller)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
/// The known set of governance actions.
///
/// As the governance logic is expanded to more runtimes, it's important to keep
/// them in sync, at least the newer ones should ensure they don't overlap with
/// the existing ones.
///
/// Existing implementations are not strongly required to be updated to be aware
/// of new actions (as they will never need to know the action indices higher
/// than the one corresponding to the current runtime), but it's good practice.
///
/// When adding a new runtime, make sure to at least update in the README.md
pub enum GovernanceAction {
    // Undefined = 0, // unused
    // EvmCall = 1, // unused
    SolanaCall = 2,
}

/// A copy of [`solana_program::instruction::AccountMeta`] with
/// `AccountSerialize`/`AccountDeserialize` impl.
/// Would be nice to just use the original, but it lacks these traits.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Debug, PartialEq, Eq)]
pub struct Acc {
    pub pubkey: Pubkey,
    pub is_signer: bool,
    pub is_writable: bool,
}

impl From<Acc> for AccountMeta {
    fn from(val: Acc) -> Self {
        let Acc {
            pubkey,
            is_signer,
            is_writable,
        } = val;
        AccountMeta {
            pubkey,
            is_signer,
            is_writable,
        }
    }
}

impl From<AccountMeta> for Acc {
    fn from(account_meta: AccountMeta) -> Acc {
        let AccountMeta {
            pubkey,
            is_signer,
            is_writable,
        } = account_meta;
        Acc {
            pubkey,
            is_signer,
            is_writable,
        }
    }
}

impl From<GovernanceMessage> for Vec<Instruction> {
    fn from(val: GovernanceMessage) -> Self {
        val.instructions.into_iter().map(|inst| inst.into()).collect()
    }
}

impl From<Vec<Instruction>> for GovernanceMessage {
    fn from(instructions: Vec<Instruction>) -> Self {
        GovernanceMessage {
            origin_caller: [0; 32],
            instructions: instructions.into_iter().map(|inst| inst.into()).collect(),
        }
    }
}

impl From<GovernanceInstruction> for Instruction {
    fn from(val: GovernanceInstruction) -> Self {
        let GovernanceInstruction {
            program_id,
            accounts,
            data,
        } = val;
        let accounts: Vec<AccountMeta> = accounts.into_iter().map(|a| a.into()).collect();
        Instruction {
            program_id,
            accounts,
            data,
        }
    }
}

impl From<Instruction> for GovernanceInstruction {
    fn from(instruction: Instruction) -> Self {
        let Instruction {
            program_id,
            accounts,
            data,
        } = instruction;

        let accounts: Vec<Acc> = accounts.into_iter().map(|a| a.into()).collect();

        GovernanceInstruction {
            program_id,
            accounts,
            data,
        }
    }
}
