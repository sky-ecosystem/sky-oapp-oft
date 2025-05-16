// SPDX-License-Identifier: Apache-2.0
use crate::{error::GovernanceError, SOLANA_CHAIN_ID};
use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;
use solana_program::pubkey::Pubkey;
use std::io;

/// General purpose governance message to call arbitrary instructions on a governed program.
/// The wire format for this message is:
/// | field           |                     size (bytes) | description                             |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | MODULE          |                               32 | Governance module identifier            |
/// | ACTION          |                                1 | Governance action identifier            |
/// | CHAIN           |                                4 | Chain identifier                        |
/// | ORIGIN_CALLER   |                               32 | Origin caller address as bytes32        |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | program_id      |                               32 | Program ID of the program to be invoked |
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data_length     |                                2 | Length of the data                      |
/// | data            |                    `data_length` | Data to be passed to the program        |
///
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
    pub origin_caller: [u8; 32],
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl GovernanceMessage {
    // "GeneralPurposeGovernance" (left padded)
    pub const MODULE: [u8; 32] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x47, 0x65, 0x6E, 0x65, 0x72, 0x61, 0x6C,
        0x50, 0x75, 0x72, 0x70, 0x6F, 0x73, 0x65, 0x47, 0x6F, 0x76, 0x65, 0x72, 0x6E, 0x61, 0x6E,
        0x63, 0x65,
    ];

    fn read_body<R: io::Read>(reader: &mut R, origin_caller: [u8; 32]) -> io::Result<Self> {
        let program_id = msg_codec::read_pubkey(reader)?;
        let accounts_len = msg_codec::read_u16(reader)?;
        let mut accounts = Vec::with_capacity(accounts_len as usize);

        for _ in 0..accounts_len {
            let pubkey = msg_codec::read_pubkey(reader)?;
            let is_signer = msg_codec::read_u8(reader)? != 0;
            let is_writable = msg_codec::read_u8(reader)? != 0;
            accounts.push(Acc {
                pubkey,
                is_signer,
                is_writable,
            });
        }

        let data_len = msg_codec::read_u16(reader)?;
        let mut data = vec![0u8; data_len as usize];
        reader.read_exact(&mut data)?;

        Ok(Self {
            origin_caller,
            program_id,
            accounts,
            data,
        })
    }

    fn write_body<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        msg_codec::write_pubkey(writer, &self.program_id)?;
        msg_codec::write_u16(writer, self.accounts.len() as u16)?;

        for acc in &self.accounts {
            msg_codec::write_pubkey(writer, &acc.pubkey)?;
            msg_codec::write_u8(writer, acc.is_signer as u8)?;
            msg_codec::write_u8(writer, acc.is_writable as u8)?;
        }

        msg_codec::write_u16(writer, self.data.len() as u16)?;
        writer.write_all(&self.data)?;
        Ok(())
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

impl From<GovernanceMessage> for Instruction {
    fn from(val: GovernanceMessage) -> Self {
        let GovernanceMessage {
            origin_caller: _,
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

impl From<Instruction> for GovernanceMessage {
    fn from(instruction: Instruction) -> GovernanceMessage {
        let Instruction {
            program_id,
            accounts,
            data,
        } = instruction;

        let accounts: Vec<Acc> = accounts.into_iter().map(|a| a.into()).collect();

        GovernanceMessage {
            origin_caller: [0; 32],
            program_id,
            accounts,
            data,
        }
    }
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

// You'll need to add this module somewhere in your codebase
pub mod msg_codec {
    use super::*;
    use std::io::{self, Read, Write};

    pub trait MessageCodec: Sized {
        fn decode<R: Read>(reader: &mut R) -> io::Result<Self>;
        fn encode<W: Write>(&self, writer: &mut W) -> io::Result<()>;
    }

    // Helper functions for common types
    pub fn read_u8<R: Read>(reader: &mut R) -> io::Result<u8> {
        let mut buf = [0u8; 1];
        reader.read_exact(&mut buf)?;
        Ok(buf[0])
    }

    pub fn read_u16<R: Read>(reader: &mut R) -> io::Result<u16> {
        let mut buf = [0u8; 2];
        reader.read_exact(&mut buf)?;
        Ok(u16::from_be_bytes(buf))
    }

    pub fn read_u32<R: Read>(reader: &mut R) -> io::Result<u32> {
        let mut buf = [0u8; 4];
        reader.read_exact(&mut buf)?;
        Ok(u32::from_be_bytes(buf))
    }

    pub fn read_pubkey<R: Read>(reader: &mut R) -> io::Result<Pubkey> {
        let mut buf = [0u8; 32];
        reader.read_exact(&mut buf)?;
        Ok(Pubkey::new_from_array(buf))
    }

    pub fn read_bytes32<R: Read>(reader: &mut R) -> io::Result<[u8; 32]> {
        let mut buf = [0u8; 32];
        reader.read_exact(&mut buf)?;
        Ok(buf)
    }

    pub fn write_u8<W: Write>(writer: &mut W, value: u8) -> io::Result<()> {
        writer.write_all(&[value])
    }

    pub fn write_u16<W: Write>(writer: &mut W, value: u16) -> io::Result<()> {
        writer.write_all(&value.to_be_bytes())
    }

    pub fn write_u32<W: Write>(writer: &mut W, value: u32) -> io::Result<()> {
        writer.write_all(&value.to_be_bytes())
    }

    pub fn write_pubkey<W: Write>(writer: &mut W, pubkey: &Pubkey) -> io::Result<()> {
        writer.write_all(&pubkey.to_bytes())
    }

    pub fn write_bytes32<W: Write>(writer: &mut W, bytes: &[u8; 32]) -> io::Result<()> {
        writer.write_all(bytes)
    }

    pub fn decode_governance(message: &[u8]) -> Result<GovernanceMessage> {
        GovernanceMessage::decode(&mut message.as_ref())
            .map_err(|_| error!(GovernanceError::InvalidGovernanceMessage))
    }

    pub fn decode_origin_caller(message: &[u8]) -> Result<[u8; 32]> {
        // Skip module (32 bytes), action (1 byte), and chain (4 bytes) to get to origin_caller
        if message.len() < 32 + 1 + 4 + 32 {
            return Err(error!(GovernanceError::InvalidGovernanceMessage));
        }
        
        // Extract origin_caller directly from the slice at offset 37 (32 + 1 + 4)
        let origin_caller_start = 32 + 1 + 4;
        let origin_caller_end = origin_caller_start + 32;
        let mut origin_caller = [0u8; 32];
        origin_caller.copy_from_slice(&message[origin_caller_start..origin_caller_end]);
        
        Ok(origin_caller)
    }
}

// Update GovernanceMessage implementation
impl msg_codec::MessageCodec for GovernanceMessage {
    fn decode<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        // Read module
        let mut module = [0u8; 32];
        reader.read_exact(&mut module)?;
        if module != Self::MODULE {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                GovernanceError::InvalidGovernanceModule.to_string(),
            ));
        }

        // Read action
        let action: u8 = msg_codec::read_u8(reader)?;
        if action != GovernanceAction::SolanaCall as u8 {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                GovernanceError::InvalidGovernanceAction.to_string(),
            ));
        }

        // Read chain
        let chain = msg_codec::read_u32(reader)?;
        if chain != SOLANA_CHAIN_ID {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                GovernanceError::InvalidGovernanceChain.to_string(),
            ));
        }

        let origin_caller = msg_codec::read_bytes32(reader)?;
        
        Self::read_body(reader, origin_caller)
    }

    fn encode<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        writer.write_all(&Self::MODULE)?;
        msg_codec::write_u8(writer, GovernanceAction::SolanaCall as u8)?; // SolanaCall
        msg_codec::write_u32(writer, SOLANA_CHAIN_ID)?; // Solana chain
        msg_codec::write_bytes32(writer, &self.origin_caller)?;
        self.write_body(writer)
    }
}

impl AnchorSerialize for GovernanceMessage {
    fn serialize<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        msg_codec::MessageCodec::encode(self, writer)
    }
}

impl AnchorDeserialize for GovernanceMessage {
    fn deserialize_reader<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        msg_codec::MessageCodec::decode(reader)
    }
}
