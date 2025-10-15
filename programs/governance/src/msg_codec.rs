// SPDX-License-Identifier: Apache-2.0
use crate::error::GovernanceError;
use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;
use solana_program::pubkey::Pubkey;
use std::io::{self, Read, Write};

/// General purpose governance message to call arbitrary instructions on a governed program.
/// The wire format for this message is:
/// | field           |                     size (bytes) | description                             |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | ORIGIN_CALLER   |                               32 | Origin caller address as bytes32        |
/// | TARGET          |                               32 | Target address as bytes32               |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data            |                        remaining | Data to be passed to the program        |
///
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
    pub origin_caller: [u8; 32],
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl GovernanceMessage {
    pub fn from_bytes(message: &[u8]) -> Result<Self> {
        Self::decode(&mut message.as_ref())
            .map_err(|_| error!(GovernanceError::InvalidGovernanceMessage))
    }

    /// Decode a full governance message (header + body).
    pub fn decode(reader: &mut &[u8]) -> io::Result<Self> {
        let origin_caller = Self::read_bytes32(reader)?;
        let program_id = Self::read_pubkey(reader)?;

        Self::read_body(reader, origin_caller, program_id)
    }

    /// Encode a full governance message (header + body).
    pub fn encode<W: Write>(&self, writer: &mut W) -> io::Result<()> {
        Self::write_bytes32(writer, &self.origin_caller)?;
        Self::write_pubkey(writer, &self.program_id)?;
        self.write_body(writer)
    }

    /// Reads ONLY the body of the message, not the header.
    pub fn read_body(reader: &mut &[u8], origin_caller: [u8; 32], program_id: Pubkey) -> io::Result<Self> {
        let accounts_len = Self::read_u16(reader)?;
        let mut accounts = Vec::with_capacity(accounts_len as usize);

        for _ in 0..accounts_len {
            let pubkey = Self::read_pubkey(reader)?;
            let is_signer = Self::read_u8(reader)? != 0;
            let is_writable = Self::read_u8(reader)? != 0;
            accounts.push(Acc {
                pubkey,
                is_signer,
                is_writable,
            });
        }

        Ok(Self {
            origin_caller,
            program_id,
            accounts,
            data: reader.to_vec(),
        })
    }

    /// Writes ONLY the body of the message, not the header.
    pub fn write_body<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        Self::write_u16(writer, self.accounts.len() as u16)?;

        for acc in &self.accounts {
            Self::write_pubkey(writer, &acc.pubkey)?;
            Self::write_u8(writer, acc.is_signer as u8)?;
            Self::write_u8(writer, acc.is_writable as u8)?;
        }

        writer.write_all(&self.data)?;
        Ok(())
    }

    /// Decodes ONLY the origin caller from the message.
    pub fn decode_origin_caller(message: &[u8]) -> Result<[u8; 32]> {
        let origin_caller_end = 32;

        if message.len() < origin_caller_end {
            return Err(error!(GovernanceError::InvalidGovernanceMessage));
        }
        
        let mut origin_caller = [0u8; 32];
        origin_caller.copy_from_slice(&message[0..origin_caller_end]);
        Ok(origin_caller)
    }

    // Helper methods for reading/writing primitive types
    fn read_u8<R: Read>(reader: &mut R) -> io::Result<u8> {
        let mut buf = [0u8; 1];
        reader.read_exact(&mut buf)?;
        Ok(buf[0])
    }

    fn read_u16<R: Read>(reader: &mut R) -> io::Result<u16> {
        let mut buf = [0u8; 2];
        reader.read_exact(&mut buf)?;
        Ok(u16::from_be_bytes(buf))
    }

    fn read_pubkey<R: Read>(reader: &mut R) -> io::Result<Pubkey> {
        let mut buf = [0u8; 32];
        reader.read_exact(&mut buf)?;
        Ok(Pubkey::new_from_array(buf))
    }

    fn read_bytes32<R: Read>(reader: &mut R) -> io::Result<[u8; 32]> {
        let mut buf = [0u8; 32];
        reader.read_exact(&mut buf)?;
        Ok(buf)
    }

    fn write_u8<W: Write>(writer: &mut W, value: u8) -> io::Result<()> {
        writer.write_all(&[value])
    }

    fn write_u16<W: Write>(writer: &mut W, value: u16) -> io::Result<()> {
        writer.write_all(&value.to_be_bytes())
    }

    fn write_pubkey<W: Write>(writer: &mut W, pubkey: &Pubkey) -> io::Result<()> {
        writer.write_all(&pubkey.to_bytes())
    }

    fn write_bytes32<W: Write>(writer: &mut W, bytes: &[u8; 32]) -> io::Result<()> {
        writer.write_all(bytes)
    }
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
