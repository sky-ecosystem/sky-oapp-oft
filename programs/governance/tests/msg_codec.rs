// SPDX-License-Identifier: Apache-2.0
#[cfg(test)]
mod test_msg_codec {
    use anchor_lang::prelude::*;
    use base64::Engine;
    use oft::instructions::SetPauseParams;
    use solana_program::pubkey::Pubkey;
    use solana_program::bpf_loader_upgradeable;
    use solana_sdk::pubkey;
    use spl_token::instruction::TokenInstruction;

    use governance::{
        msg_codec::{Acc, GovernanceMessage},
        OWNER_PLACEHOLDER, PAYER_PLACEHOLDER,
    };
    
    const GOVERNANCE_OAPP_ADDRESS: Pubkey = pubkey!("3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a");
    const OFT_PROGRAM_ID: Pubkey = pubkey!("E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2");
    const OFT_STORE_ADDRESS: Pubkey = pubkey!("HUPW9dJZxxSafEVovebGxgbac3JamjMHXiThBxY5u43M");
    const PAYER: Pubkey = pubkey!("Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8");

    #[test]
    fn test_governance_module() {
        let s = "GeneralPurposeGovernance";
        let mut module = [0; 32];
        module[32 - s.len()..].copy_from_slice(s.as_bytes());
        assert_eq!(module, GovernanceMessage::MODULE);
    }

    #[test]
    fn test_governance_message_hello_world() {
        // hello world program id
        let program_id = Pubkey::try_from("3ynNB373Q3VAzKp7m4x238po36hjAGFXFJB4ybN2iTyg").unwrap();
        let accounts = vec![
            // owner placeholder
            Acc {
                pubkey: OWNER_PLACEHOLDER,
                is_signer: true,
                is_writable: true,
            },
            // payer placeholder
            Acc {
                pubkey: PAYER_PLACEHOLDER,
                is_signer: false,
                is_writable: true,
            },
            // hello world program id
            Acc {
                pubkey: program_id,
                is_signer: false,
                is_writable: false,
            },
        ];
        // Anchor example hello world "Initialize" instruction data that logs "Greetings"
        let data = hex::decode("afaf6d1f0d989bed").unwrap();
        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id,
            accounts,
            data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized message: {:?}", hex::encode(&buf));

        let msg2 = GovernanceMessage::deserialize(&mut buf.as_slice()).unwrap();
        assert_eq!(msg, msg2);
    }

    #[test]
    fn test_governance_message_parse() {
        let program_id_as_hex = hex::encode(Pubkey::try_from(governance::ID).unwrap().to_bytes());
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
            governance_program_id: governance::ID,
            program_id: Pubkey::try_from("1111111QLbz7JHiBTspS962RLKV8GndWFwiEaqKM").unwrap(),
            accounts,
            data,
        };

        assert_eq!(actual, expected)
    }

    #[test]
    fn test_governance_message_transfer_token() {
        let mint_pubkey = Pubkey::try_from("AtGakZsHVY1BkinHEFMEJxZYhwA9KnuLD8QRmGjSAZEC").unwrap();
        let mint_account = Acc {
            pubkey: mint_pubkey,
            is_signer: false,
            is_writable: false,
        };
        let owner_account = Acc {
            pubkey: OWNER_PLACEHOLDER,
            is_signer: true,
            is_writable: false,
        };

        let (associated_token_address, _bump_seed) = Pubkey::find_program_address(
            &[
                GOVERNANCE_OAPP_ADDRESS.as_ref(),
                spl_token::id().as_ref(),
                mint_pubkey.as_ref(),
            ],
            &spl_associated_token_account::id(),
        );

        let token_account = Acc {
            pubkey: associated_token_address,
            is_signer: false,
            is_writable: true,
        };

        let destination_account = Acc {
            pubkey: Pubkey::try_from("3Qq7GD6V3mK1do7Ch7JMr9LdUu4Lv3EZ4qJcggw1eyR6").unwrap(),
            is_signer: false,
            is_writable: true,
        };
        let amount_to_transfer = 10u64;

        let accounts = vec![
            // SPL token source account
            token_account.clone(),
            // SPL token mint
            mint_account.clone(),
            // destination ATA
            destination_account.clone(),
            // signer
            owner_account.clone(),
        ];

        let instruction_data = TokenInstruction::TransferChecked {
            amount: amount_to_transfer,
            decimals: 9,
        }
        .pack();

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: spl_token::id(),
            accounts: accounts.clone(),
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));
    }

    #[test]
    fn test_governance_message_upgrade_program<'a>() {
        let buffer_address = pubkey!("6yfcTwqobTw9CP2etWDuogMbjinp63Ea4DbQKX5W3DNL");

        let instruction = bpf_loader_upgradeable::upgrade(&OFT_PROGRAM_ID, &buffer_address, &OWNER_PLACEHOLDER, &GOVERNANCE_OAPP_ADDRESS);

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: bpf_loader_upgradeable::id(),
            accounts: instruction.accounts.iter().map(|a| Acc {
                pubkey: a.pubkey,
                is_signer: a.is_signer,
                is_writable: a.is_writable,
            }).collect(),
            data: instruction.data.clone(),
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        // prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_transfer_upgrade_authority<'a>() {
        let instruction = bpf_loader_upgradeable::set_upgrade_authority(&OFT_PROGRAM_ID, &OWNER_PLACEHOLDER, Some(&pubkey!("Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8")));

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: bpf_loader_upgradeable::id(),
            accounts: instruction.accounts.iter().map(|a| Acc {
                pubkey: a.pubkey,
                is_signer: a.is_signer,
                is_writable: a.is_writable,
            }).collect(),
            data: instruction.data.clone(),
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        // prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_pause_oft<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_pause");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let set_pause_params = SetPauseParams {
            paused: true,
        };

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&set_pause_params, &mut instruction_data)
            .expect("Failed to serialize SetPauseParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        let accounts = vec![
            // signer
            Acc {
                pubkey: OWNER_PLACEHOLDER,
                is_signer: true,
                is_writable: false,
            },
            // OFT store account
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: true,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: OFT_PROGRAM_ID,
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        // prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_unpause_oft<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_pause");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let set_pause_params = SetPauseParams {
            paused: false,
        };

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&set_pause_params, &mut instruction_data)
            .expect("Failed to serialize SetPauseParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        let accounts = vec![
            // signer
            Acc {
                pubkey: OWNER_PLACEHOLDER,
                is_signer: true,
                is_writable: false,
            },
            // OFT store account
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: true,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: OFT_PROGRAM_ID,
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        // prepare_governance_message_simulation(&msg);
    }

    pub fn sighash(namespace: &str, name: &str) -> [u8; 8] {
        let preimage = format!("{}:{}", namespace, name);

        let mut sighash = [0u8; 8];
        sighash.copy_from_slice(
            &anchor_lang::solana_program::hash::hash(preimage.as_bytes()).to_bytes()[..8],
        );
        sighash
    }

    // Function to convert EVM address to bytes32
    fn evm_address_to_bytes32(address: &str) -> [u8; 32] {
        let mut result = [0u8; 32];

        // Remove '0x' prefix if present
        let clean_address = if address.starts_with("0x") {
            &address[2..]
        } else {
            address
        };

        // Decode the hex string
        let decoded = hex::decode(clean_address).expect("Invalid hex in EVM address");

        // EVM addresses are 20 bytes, so we copy to the last 20 bytes of the 32-byte array
        // This is the standard way to represent EVM addresses in a bytes32
        if decoded.len() == 20 {
            result[12..32].copy_from_slice(&decoded);
        } else {
            panic!("EVM address must be 20 bytes (40 hex chars)");
        }

        result
    }

    fn prepare_governance_message_simulation(message: &GovernanceMessage) {
        use solana_sdk::transaction::Transaction;
        use solana_sdk::instruction::Instruction;

        let tx = Transaction::new_with_payer(
            &[Instruction {
                program_id: message.program_id,
                accounts: message.accounts.iter().map(|a| AccountMeta {
                    pubkey: if a.pubkey == OWNER_PLACEHOLDER {
                        GOVERNANCE_OAPP_ADDRESS
                    } else {
                        a.pubkey
                    },
                    is_signer: a.is_signer,
                    is_writable: a.is_writable,
                }).collect(),
                data: message.data.clone(),
            }],
            Some(&PAYER),
        );
    
        println!("{}", base64::engine::general_purpose::STANDARD.encode(tx.message_data()));
    }
}
