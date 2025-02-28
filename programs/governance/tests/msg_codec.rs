#[cfg(test)]
mod test_msg_codec {
    use anchor_lang::prelude::*;
    use oft::SendParams;
    use solana_program::pubkey::Pubkey;
    use spl_token::instruction::TokenInstruction;

    use governance::{
        msg_codec::{Acc, GovernanceMessage},
        OWNER_PLACEHOLDER, PAYER_PLACEHOLDER,
    };

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
        let governance_oapp_address =
            Pubkey::try_from("3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a").unwrap();
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
                governance_oapp_address.as_ref(),
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
    fn test_governance_message_init_oft_two_leg_send<'a>() {
        let governance_oapp_address =
            Pubkey::try_from("3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a").unwrap();
        let oft_spl_mint_address =
            Pubkey::try_from("AtGakZsHVY1BkinHEFMEJxZYhwA9KnuLD8QRmGjSAZEC").unwrap();
        let oft_program_address = oft::ID;

        let (governance_ata_address, _bump_seed) = Pubkey::find_program_address(
            &[
                governance_oapp_address.as_ref(),
                // owner_account.pubkey.as_ref(),
                spl_token::id().as_ref(),
                oft_spl_mint_address.as_ref(),
            ],
            &spl_associated_token_account::id(),
        );

        let accounts = vec![
            // signer
            Acc {
                pubkey: OWNER_PLACEHOLDER,
                is_signer: true,
                is_writable: false,
            },
            // peer account
            Acc {
                pubkey: Pubkey::default(), // @TODO: change to the peer account
                is_signer: false,
                is_writable: false,
            },
            // OFT store account
            Acc {
                pubkey: Pubkey::default(), // @TODO: change to the OFT store account
                is_signer: false,
                is_writable: false,
            },
            // SPL token source account
            Acc {
                pubkey: governance_ata_address,
                is_signer: false,
                is_writable: true,
            },
            // SPL token escrow account
            Acc {
                pubkey: Pubkey::default(), // @TODO: change to the escrow account
                is_signer: false,
                is_writable: true,
            },
            // SPL token mint
            Acc {
                pubkey: oft_spl_mint_address,
                is_signer: false,
                is_writable: false,
            },
            // token program
            Acc {
                pubkey: spl_token::id(),
                is_signer: false,
                is_writable: false,
            },
        ];

        let send_params = SendParams {
            to: [0; 32],
            options: vec![],
            compose_msg: None,
            native_fee: 0,
            lz_token_fee: 0,
            amount_ld: 1000,
            min_amount_ld: 1000,
            dst_eid: 0,
        };

        pub fn sighash(namespace: &str, name: &str) -> [u8; 8] {
            let preimage = format!("{}:{}", namespace, name);

            let mut sighash = [0u8; 8];
            sighash.copy_from_slice(
                &anchor_lang::solana_program::hash::hash(preimage.as_bytes()).to_bytes()[..8],
            );
            sighash
        }
        let mut instruction_data = Vec::new();

        let discriminator = sighash("global", "init_two_leg_send");

        // Add the discriminator
        instruction_data.extend_from_slice(&discriminator);

        // Serialize the SendParams struct using Borsh
        borsh::BorshSerialize::serialize(&send_params, &mut instruction_data)
            .expect("Failed to serialize SendParams");

        println!("Instruction data (hex): {}", hex::encode(&instruction_data));

        // let mut accounts_metas: Vec<AccountMeta> = Vec::with_capacity(accounts.len());
        // for account in accounts.iter() {
        //     if account.is_writable {
        //         accounts_metas.push(AccountMeta::new(account.pubkey, account.is_signer));
        //     } else {
        //         accounts_metas.push(AccountMeta::new_readonly(account.pubkey, account.is_signer));
        //     }
        // }

        // // let account_infos = accounts_metas.to_account_infos();

        // let lamports = Rc::new(RefCell::new(1_000_000));
        // let data = Rc::new(RefCell::new(vec![0; 32]));
        // let owner = Rc::new(Pubkey::default());

        // let account_infos: Vec<AccountInfo<'a>> = accounts_metas.iter().map(|meta| {
        //     AccountInfo::new(
        //         &meta.pubkey,
        //         meta.is_signer,
        //         meta.is_writable,
        //         &mut *lamports.borrow_mut(),
        //         &mut *data.borrow_mut(),
        //         &owner,
        //         false,
        //         Epoch::default(),
        //     )
        // }).collect();

        // let cpi_ctx = InitTwoLegSend::construct_context(oft_program_address, &account_infos).unwrap();

        // construct the init_two_leg_send instruction
        // let init_two_leg_send_ix = oft::cpi::init_two_leg_send(
        //     cpi_ctx,
        //     SendParams {
        //         to: [0; 32],
        //         options: vec![],
        //         compose_msg: None,
        //         native_fee: 0,
        //         lz_token_fee: 0,
        //         amount_ld: 0,
        //         dst_eid: 0,
        //         min_amount_ld: 0,
        //     }
        // ).unwrap();

        // let transfer_ix = spl_token::instruction::transfer_checked(
        //     &spl_token::ID,
        //     &token_account.pubkey,
        //     &mint_pubkey,
        //     &destination_account.pubkey,
        //     &Pubkey::try_from("3qsePQwjm5kABtgHoq5ksNj2JbYQ8sczff25Q7gqX74a").unwrap(),
        //     &[],
        //     amount_to_transfer,
        //     9,
        // ).unwrap();
    }
}
