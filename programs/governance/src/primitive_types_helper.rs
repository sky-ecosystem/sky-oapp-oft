// SPDX-License-Identifier: Apache-2.0
use std::io::{self, Read, Write};
use solana_program::pubkey::Pubkey;

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

pub fn write_pubkey<W: Write>(writer: &mut W, pubkey: &Pubkey) -> io::Result<()> {
    writer.write_all(&pubkey.to_bytes())
}

pub fn write_bytes32<W: Write>(writer: &mut W, bytes: &[u8; 32]) -> io::Result<()> {
    writer.write_all(bytes)
}

pub fn read_u32<R: Read>(reader: &mut R) -> io::Result<u32> {
    let mut buf = [0u8; 4];
    reader.read_exact(&mut buf)?;
    Ok(u32::from_be_bytes(buf))
}

pub fn write_u32<W: Write>(writer: &mut W, value: u32) -> io::Result<()> {
    writer.write_all(&value.to_be_bytes())
}
