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
/// | ACTION          |                                1 | Governance action identifier            |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | program_id      |                               32 | Program ID of the program to be invoked |
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data            |                        remaining | Data to be passed to the program        |
///
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
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
        let action: u8 = Self::read_u8(reader)?;
        if action != GovernanceAction::SolanaCall as u8 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                GovernanceError::InvalidGovernanceAction.to_string(),
            ));
        }

        Self::read_body(reader)
    }

    /// Encode a full governance message (header + body).
    pub fn encode<W: Write>(&self, writer: &mut W) -> io::Result<()> {
        Self::write_u8(writer, GovernanceAction::SolanaCall as u8)?;
        self.write_body(writer)
    }

    /// Reads ONLY the body of the message, not the header.
    fn read_body(reader: &mut &[u8]) -> io::Result<Self> {
        let program_id = Self::read_pubkey(reader)?;
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
            program_id,
            accounts,
            data: reader.to_vec(),
        })
    }

    /// Writes ONLY the body of the message, not the header.
    fn write_body<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        Self::write_pubkey(writer, &self.program_id)?;
        Self::write_u16(writer, self.accounts.len() as u16)?;

        for acc in &self.accounts {
            Self::write_pubkey(writer, &acc.pubkey)?;
            Self::write_u8(writer, acc.is_signer as u8)?;
            Self::write_u8(writer, acc.is_writable as u8)?;
        }

        writer.write_all(&self.data)?;
        Ok(())
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

    fn read_u32<R: Read>(reader: &mut R) -> io::Result<u32> {
        let mut buf = [0u8; 4];
        reader.read_exact(&mut buf)?;
        Ok(u32::from_be_bytes(buf))
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

    fn write_u32<W: Write>(writer: &mut W, value: u32) -> io::Result<()> {
        writer.write_all(&value.to_be_bytes())
    }

    fn write_pubkey<W: Write>(writer: &mut W, pubkey: &Pubkey) -> io::Result<()> {
        writer.write_all(&pubkey.to_bytes())
    }

    fn write_bytes32<W: Write>(writer: &mut W, bytes: &[u8; 32]) -> io::Result<()> {
        writer.write_all(bytes)
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
