use crate::{SOLANA_CHAIN_ID, error::GovernanceError};
use std::io;
use anchor_lang::prelude::*;
use solana_program::instruction::Instruction;

/// General purpose governance message to call arbitrary instructions on a governed program.
/// The wire format for this message is:
/// | field           |                     size (bytes) | description                             |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | MODULE          |                               32 | Governance module identifier            |
/// | ACTION          |                                1 | Governance action identifier            |
/// | CHAIN           |                                4 | Chain identifier                        |
/// |-----------------+----------------------------------+-----------------------------------------|
/// | program_id      |                               32 | Program ID of the program to be invoked |
/// | accounts_length |                                2 | Number of accounts                      |
/// | accounts        | `accounts_length` * (32 + 1 + 1) | Accounts to be passed to the program    |
/// | data_length     |                                2 | Length of the data                      |
/// | data            |                    `data_length` | Data to be passed to the program        |
///
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GovernanceMessage {
    pub governance_program_id: Pubkey,
    pub program_id: Pubkey,
    pub accounts: Vec<Acc>,
    pub data: Vec<u8>,
}

impl GovernanceMessage {
    // "GeneralPurposeGovernance" (left padded)
    const MODULE: [u8; 32] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x47, 0x65, 0x6E, 0x65, 0x72, 0x61, 0x6C,
        0x50, 0x75, 0x72, 0x70, 0x6F, 0x73, 0x65, 0x47, 0x6F, 0x76, 0x65, 0x72, 0x6E, 0x61, 0x6E,
        0x63, 0x65,
    ];

    fn read_body<R: io::Read>(reader: &mut R, governance_program_id: Pubkey) -> io::Result<Self> {
        let program_id = msg_codec::read_pubkey(reader)?;
        let accounts_len = msg_codec::read_u16(reader)?;
        let mut accounts = Vec::with_capacity(accounts_len as usize);
        
        for _ in 0..accounts_len {
            let pubkey = msg_codec::read_pubkey(reader)?;
            let is_signer = msg_codec::read_u8(reader)? != 0;
            let is_writable = msg_codec::read_u8(reader)? != 0;
            accounts.push(Acc { pubkey, is_signer, is_writable });
        }

        let data_len = msg_codec::read_u16(reader)?;
        let mut data = vec![0u8; data_len as usize];
        reader.read_exact(&mut data)?;

        Ok(Self { governance_program_id, program_id, accounts, data })
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

#[test]
fn test_governance_module() {
    let s = "GeneralPurposeGovernance";
    let mut module = [0; 32];
    module[32 - s.len()..].copy_from_slice(s.as_bytes());
    assert_eq!(module, GovernanceMessage::MODULE);
}

#[test]
fn test_governance_message_serde() {
    let program_id = Pubkey::new_unique();
    let accounts = vec![
        Acc {
            pubkey: Pubkey::new_unique(),
            is_signer: true,
            is_writable: true,
        },
        Acc {
            pubkey: Pubkey::new_unique(),
            is_signer: false,
            is_writable: true,
        },
    ];
    let data = vec![1, 2, 3, 4, 5];
    let msg = GovernanceMessage {
        governance_program_id: crate::ID,
        program_id,
        accounts,
        data,
    };

    let mut buf = Vec::new();
    msg.serialize(&mut buf).unwrap();

    let msg2 = GovernanceMessage::deserialize(&mut buf.as_slice()).unwrap();
    assert_eq!(msg, msg2);
}

#[test]
fn test_governance_message_parse() {
    let program_id_as_hex = hex::encode(Pubkey::try_from(crate::ID).unwrap().to_bytes());
    let hex_string = format!(
        "000000000000000047656e6572616c507572706f7365476f7665726e616e636502{:08x}{}00000000000000010000000000000000000000000000000000000000000000000002000000000000000200000000000000000000000000000000000000000000000001010000000000000003000000000000000000000000000000000000000000000000000100050102030405",
        40168u32,
        program_id_as_hex
    );
    let h = hex::decode(hex_string).unwrap();

    let actual = GovernanceMessage::deserialize(&mut h.as_slice()).unwrap();

    let accounts = vec![
        Acc {
            pubkey: Pubkey::try_from("1111111ogCyDbaRMvkdsHB3qfdyFYaG1WtRUAfdh").unwrap(),
            is_signer: true,
            is_writable: true,
        },
        Acc {
            pubkey: Pubkey::try_from("11111112D1oxKts8YPdTJRG5FzxTNpMtWmq8hkVx3").unwrap(),
            is_signer: false,
            is_writable: true,
        },
    ];
    let data = vec![1, 2, 3, 4, 5];
    let expected = GovernanceMessage {
        governance_program_id: crate::ID,
        program_id: Pubkey::try_from("1111111QLbz7JHiBTspS962RLKV8GndWFwiEaqKM").unwrap(),
        accounts,
        data,
    };

    assert_eq!(actual, expected)
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
            governance_program_id,
            program_id,
            accounts,
            data,
        } = val;
        assert_eq!(governance_program_id, crate::ID);
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
            governance_program_id: crate::ID,
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
        fn encoded_size(&self) -> usize;
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

    pub fn decode_governance(message: &[u8]) -> Result<GovernanceMessage> {
        GovernanceMessage::decode(&mut message.as_ref())
            .map_err(|_| error!(GovernanceError::InvalidGovernanceMessage))
    }
}

// Update GovernanceMessage implementation
impl msg_codec::MessageCodec for GovernanceMessage {
    fn decode<R: io::Read>(reader: &mut R) -> io::Result<Self> {
        // Read module
        let mut module = [0u8; 32];
        reader.read_exact(&mut module)?;
        if module != Self::MODULE {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceMessage module",
            ));
        }

        // Read action
        let action: u8 = msg_codec::read_u8(reader)?;
        if action != GovernanceAction::SolanaCall as u8 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceAction",
            ));
        }

        // Read chain
        let chain = msg_codec::read_u32(reader)?;
        if chain != SOLANA_CHAIN_ID { // Solana
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "Invalid GovernanceMessage chain",
            ));
        }

        let governance_program_id = msg_codec::read_pubkey(reader)?;
        Self::read_body(reader, governance_program_id)
    }

    fn encode<W: io::Write>(&self, writer: &mut W) -> io::Result<()> {
        writer.write_all(&Self::MODULE)?;
        msg_codec::write_u8(writer, GovernanceAction::SolanaCall as u8)?; // SolanaCall
        msg_codec::write_u32(writer, SOLANA_CHAIN_ID)?; // Solana chain
        msg_codec::write_pubkey(writer, &self.governance_program_id)?;
        self.write_body(writer)
    }

    fn encoded_size(&self) -> usize {
        32 // MODULE
        + 1 // action
        + 4 // chain
        + 32 // governance_program_id
        + 32 // program_id
        + 2 // accounts_length
        + self.accounts.len() * (32 + 1 + 1) // accounts (pubkey + is_signer + is_writable)
        + 2 // data_length
        + self.data.len() // data
    }
}

// Update AnchorSerialize/Deserialize implementations
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
