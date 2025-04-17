// SPDX-License-Identifier: Apache-2.0
#[cfg(test)]
mod test_msg_codec {
    use anchor_lang::prelude::*;
    use base64::Engine;
    use oapp::endpoint::{self, instructions::{InitReceiveLibraryParams, InitSendLibraryParams, SetReceiveLibraryParams, SetSendLibraryParams}, SetConfigParams, MESSAGE_LIB_SEED, OAPP_SEED, RECEIVE_LIBRARY_CONFIG_SEED, SEND_LIBRARY_CONFIG_SEED};
    use oft::{instructions::{PeerConfigParam, SetOFTConfigParams, SetPauseParams, SetPeerConfigParams}, PEER_SEED};
    use solana_program::pubkey::Pubkey;
    use solana_program::bpf_loader_upgradeable;
    use solana_sdk::pubkey;
    use spl_token::instruction::TokenInstruction;

    use governance::{
        msg_codec::{Acc, GovernanceMessage}, CPI_AUTHORITY_SEED, GOVERNANCE_SEED, CPI_AUTHORITY_PLACEHOLDER, PAYER_PLACEHOLDER
    };
    use uln::state::UlnConfig;
    
    const OFT_STORE_ADDRESS: Pubkey = pubkey!("6wDD73dAoR1DC8TgKuQGqCp5mBfQmTrfipPotyxUnrBk");
    const PAYER: Pubkey = pubkey!("Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8");
    const BNB_TESTNET_EID: u32 = 40102;
    const FUJI_EID: u32 = 40106;
    const CONFIG_TYPE_SEND_ULN: u32 = 1;

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
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
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
            pubkey: CPI_AUTHORITY_PLACEHOLDER,
            is_signer: true,
            is_writable: false,
        };

        let (associated_token_address, _bump_seed) = Pubkey::find_program_address(
            &[
                get_governance_oapp_pda().0.as_ref(),
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

        let (governance_oapp_address, _bump_seed) = get_governance_oapp_pda();
        let instruction = bpf_loader_upgradeable::upgrade(&oft::id(), &buffer_address, &CPI_AUTHORITY_PLACEHOLDER, &governance_oapp_address);

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
        let instruction = bpf_loader_upgradeable::set_upgrade_authority(&oft::id(), &CPI_AUTHORITY_PLACEHOLDER, Some(&pubkey!("Fty7h4FYAN7z8yjqaJExMHXbUoJYMcRjWYmggSxLbHp8")));

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
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
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
            program_id: oft::id(),
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
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
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
            program_id: oft::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        // prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_delegate() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_oft_config");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let params = SetOFTConfigParams::Delegate(get_cpi_authority());

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetOFTConfigParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        let accounts = vec![
            // admin as signer
            Acc {
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
                is_signer: true,
                is_writable: false,
            },
            // OFT store account
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: true,
            },
            Acc {
                pubkey: endpoint::id(),
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: true,
            },
            // oapp registry account
            Acc {
                pubkey: get_oft_oapp_registry(),
                is_signer: false,
                is_writable: true,
            },
            // event authority account
            Acc {
                pubkey: pubkey!("F8E8QGhKmHEx2esh5LpVizzcP4cHYhzXdXTwg9w3YYY2"),
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: endpoint::id(),
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: oft::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_admin<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_oft_config");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let params = SetOFTConfigParams::Admin(get_cpi_authority());

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetOFTConfigParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        let accounts = vec![
            // admin as signer
            Acc {
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
                is_signer: true,
                is_writable: false,
            },
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: true,
            }
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: oft::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_peer_address<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_peer_config");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let params = SetPeerConfigParams {
            remote_eid: 7771,
            config: PeerConfigParam::PeerAddress(evm_address_to_bytes32("0x89e5fD9975e67A27dbbd2af085f4a5627AC14eD9")),
        };

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetPeerConfigParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        println!("OFT Program ID: {:?}", oft::id());

        let (peer_address, _bump_seed) = Pubkey::find_program_address(
            &[
                PEER_SEED,
                &OFT_STORE_ADDRESS.to_bytes(),
                &params.remote_eid.to_be_bytes(),
            ],
            &oft::id(),
        );

        let accounts = vec![
            // admin as signer
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: true,
            },
            // peer
            Acc {
                pubkey: peer_address,
                is_signer: false,
                is_writable: true,
            },
            // OFT store account
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: false,
            },
            // system program
            Acc {
                pubkey: solana_program::system_program::ID,
                is_signer: false,
                is_writable: false,
            },
        ];

        println!("Peer address: {:?}", peer_address);

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: oft::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_oapp_config<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_config");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let config = UlnConfig {
            confirmations: 1,
            required_dvn_count: 1,
            optional_dvn_count: 0,
            optional_dvn_threshold: 0,
            required_dvns: vec![
                pubkey!("4VDjp6XQaxoZf5RGwiPU9NR1EXSZn2TP4ATMmiSzLfhb")
            ],
            optional_dvns: vec![],
        };

        let mut config_bytes = Vec::new();
        config.serialize(&mut config_bytes).unwrap();

        let params = SetConfigParams {
            oapp: get_governance_oapp_pda().0,
            eid: FUJI_EID,
            config_type: CONFIG_TYPE_SEND_ULN,
            config: config_bytes,
        };

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetPeerConfigParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        println!("OFT Program ID: {:?}", oft::id());

        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                params.oapp.as_ref()
            ],
            &endpoint::id(),
        );

        let message_lib_key = pubkey!("7a4WjyR8VZ7yZz5XJAKm39BUGn5iT9CKcv2pmG9tdXVH");

        let (message_lib_info, _bump_seed) = Pubkey::find_program_address(
            &[
                MESSAGE_LIB_SEED,
                message_lib_key.to_bytes().as_ref()
            ],
            &endpoint::id(),
        );

        let accounts = vec![
            // The PDA of the OApp or delegate
            Acc {
                pubkey: CPI_AUTHORITY_PLACEHOLDER,
                is_signer: true,
                is_writable: true,
            },
            // OApp registry account
            Acc {
                pubkey: oapp_registry,
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: message_lib_info,
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: endpoint::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_init_send_library<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "init_send_library");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let governance_oapp_address = get_governance_oapp_pda().0;
        let governance_oapp_bump = get_governance_oapp_pda().1;
        println!("Governance OApp address: {:?}", governance_oapp_address);
        println!("Governance OApp bump: {:?}", governance_oapp_bump);

        let cpi_authority_address = get_cpi_authority();
        println!("CPI authority address: {:?}", cpi_authority_address);

        let params = InitSendLibraryParams {
            sender: OFT_STORE_ADDRESS,
            eid: 777,
        };

        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize InitSendLibraryParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        println!("OFT Program ID: {:?}", oft::id());

        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                params.sender.as_ref()
            ],
            &endpoint::id(),
        );

        let (send_library_config, _bump_seed) = Pubkey::find_program_address(
            &[
                SEND_LIBRARY_CONFIG_SEED,
                &params.sender.to_bytes(),
                &params.eid.to_be_bytes()
            ],
            &endpoint::id(),
        );

        let accounts = vec![
            // The PDA of the OApp or delegate
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: true,
            },
            // OApp registry account
            Acc {
                pubkey: oapp_registry,
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: send_library_config,
                is_signer: false,
                is_writable: true,
            },
            Acc {
                pubkey: solana_program::system_program::ID,
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: endpoint::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_init_receive_library<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "init_receive_library");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let governance_oapp_address = get_governance_oapp_pda().0;
        let governance_oapp_bump = get_governance_oapp_pda().1;
        println!("Governance OApp address: {:?}", governance_oapp_address);
        println!("Governance OApp bump: {:?}", governance_oapp_bump);

        let cpi_authority_address = get_cpi_authority();
        println!("CPI authority address: {:?}", cpi_authority_address);

        let params = InitReceiveLibraryParams {
            eid: FUJI_EID,
            receiver: OFT_STORE_ADDRESS,
        };

        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize InitReceiveLibraryParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        println!("OFT Program ID: {:?}", oft::id());

        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                params.receiver.as_ref()
            ],
            &endpoint::id(),
        );

        let (receive_library_config, _bump_seed) = Pubkey::find_program_address(
            &[
                RECEIVE_LIBRARY_CONFIG_SEED,
                &params.receiver.to_bytes(),
                &params.eid.to_be_bytes()
            ],
            &endpoint::id(),
        );

        let accounts = vec![
            // The PDA of the OApp or delegate
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: true,
            },
            // OApp registry account
            Acc {
                pubkey: oapp_registry,
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: receive_library_config,
                is_signer: false,
                is_writable: true,
            },
            Acc {
                pubkey: solana_program::system_program::ID,
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: endpoint::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_send_library<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_send_library");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let params = SetSendLibraryParams {
            sender: OFT_STORE_ADDRESS,
            eid: FUJI_EID,
            new_lib: pubkey!("2XgGZG4oP29U3w5h4nTk1V2LFHL23zKDPJjs3psGzLKQ"),
        };

        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetSendLibraryParams");

        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                params.sender.as_ref()
            ],
            &endpoint::id(),
        );

        let (send_library_config, _bump_seed) = Pubkey::find_program_address(
            &[
                SEND_LIBRARY_CONFIG_SEED,
                &params.sender.to_bytes(),
                &params.eid.to_be_bytes()
            ],
            &endpoint::id(),
        );

        let (message_lib_info, _bump_seed) = Pubkey::find_program_address(
            &[
                MESSAGE_LIB_SEED,
                params.new_lib.to_bytes().as_ref()
            ],
            &endpoint::id(),
        );

        let accounts = vec![
            // The PDA of the OApp or delegate
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: false,
            },
            // OApp registry account
            Acc {
                pubkey: oapp_registry,
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: send_library_config,
                is_signer: false,
                is_writable: true,
            },
            // message lib info
            Acc {
                pubkey: message_lib_info,
                is_signer: false,
                is_writable: false,
            },
            // event authority account
            Acc {
                pubkey: pubkey!("F8E8QGhKmHEx2esh5LpVizzcP4cHYhzXdXTwg9w3YYY2"),
                is_signer: false,
                is_writable: false,
            },
            // endpoint account
            Acc {
                pubkey: endpoint::id(),
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: endpoint::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }

    #[test]
    fn test_governance_message_set_receive_library<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_receive_library");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let params = SetReceiveLibraryParams {
            receiver: OFT_STORE_ADDRESS,
            eid: FUJI_EID,
            new_lib: pubkey!("2XgGZG4oP29U3w5h4nTk1V2LFHL23zKDPJjs3psGzLKQ"),
            grace_period: 0,
        };

        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetReceiveLibraryParams");

        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                params.receiver.as_ref()
            ],
            &endpoint::id(),
        );

        let (receive_library_config, _bump_seed) = Pubkey::find_program_address(
            &[
                RECEIVE_LIBRARY_CONFIG_SEED,
                &params.receiver.to_bytes(),
                &params.eid.to_be_bytes()
            ],
            &endpoint::id(),
        );

        let (message_lib_info, _bump_seed) = Pubkey::find_program_address(
            &[
                MESSAGE_LIB_SEED,
                params.new_lib.to_bytes().as_ref()
            ],
            &endpoint::id(),
        );

        let accounts = vec![
            // The PDA of the OApp or delegate
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: false,
            },
            // OApp registry account
            Acc {
                pubkey: oapp_registry,
                is_signer: false,
                is_writable: false,
            },
            Acc {
                pubkey: receive_library_config,
                is_signer: false,
                is_writable: true,
            },
            // message lib info
            Acc {
                pubkey: message_lib_info,
                is_signer: false,
                is_writable: false,
            },
            // event authority account
            Acc {
                pubkey: pubkey!("F8E8QGhKmHEx2esh5LpVizzcP4cHYhzXdXTwg9w3YYY2"),
                is_signer: false,
                is_writable: false,
            },
            // endpoint account
            Acc {
                pubkey: endpoint::id(),
                is_signer: false,
                is_writable: false,
            },
        ];

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: endpoint::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
    }


    #[test]
    fn test_governance_message_set_enforced_options<'a>() {
        let mut instruction_data = Vec::new();
        let discriminator = sighash("global", "set_peer_config");
        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        let send_options = hex::decode("00030100110100000000000000000000000000013880").unwrap();
        let empty_options = hex::decode("0003").unwrap();

        let params = SetPeerConfigParams {
            remote_eid: FUJI_EID,
            config: PeerConfigParam::EnforcedOptions {
                send: send_options,
                send_and_call: empty_options,
            },
        };

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&params, &mut instruction_data)
            .expect("Failed to serialize SetPeerConfigParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        println!("OFT Program ID: {:?}", oft::id());

        let (peer_address, _bump_seed) = Pubkey::find_program_address(
            &[
                PEER_SEED,
                &OFT_STORE_ADDRESS.to_bytes(),
                &params.remote_eid.to_be_bytes(),
            ],
            &oft::id(),
        );

        let accounts = vec![
            // admin as signer
            Acc {
                pubkey: get_cpi_authority(),
                is_signer: true,
                is_writable: true,
            },
            // peer
            Acc {
                pubkey: peer_address,
                is_signer: false,
                is_writable: true,
            },
            // OFT store account
            Acc {
                pubkey: OFT_STORE_ADDRESS,
                is_signer: false,
                is_writable: false,
            },
            // system program
            Acc {
                pubkey: solana_program::system_program::ID,
                is_signer: false,
                is_writable: false,
            },
        ];

        println!("Peer address: {:?}", peer_address);

        let msg = GovernanceMessage {
            governance_program_id: governance::ID,
            program_id: oft::id(),
            accounts: accounts,
            data: instruction_data,
        };

        let mut buf = Vec::new();
        msg.serialize(&mut buf).unwrap();

        println!("Serialized governance message: {:?}", hex::encode(&buf));

        prepare_governance_message_simulation(&msg);
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
                    pubkey: if a.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                        get_cpi_authority()
                    } else if a.pubkey == PAYER_PLACEHOLDER {
                        PAYER
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

    fn get_cpi_authority() -> Pubkey {
        let cpi_authority = Pubkey::create_program_address(&[CPI_AUTHORITY_SEED, get_governance_oapp_pda().0.to_bytes().as_ref(), &[get_governance_oapp_pda().1]], &governance::id()).unwrap();

        cpi_authority
    }

    fn get_oft_oapp_registry() -> Pubkey {
        let (oapp_registry, _bump_seed) = Pubkey::find_program_address(
            &[
                OAPP_SEED,
                OFT_STORE_ADDRESS.as_ref()
            ],
            &endpoint::id(),
        );

        oapp_registry
    }

    fn get_governance_oapp_pda() -> (Pubkey, u8) {
        let governance_id: u8 = 0;
        let (governance_oapp_address, bump_seed) = Pubkey::find_program_address(
            &[
                GOVERNANCE_SEED,
                &governance_id.to_be_bytes()
            ],
            &governance::id(),
        );

        (governance_oapp_address, bump_seed)
    }
}
