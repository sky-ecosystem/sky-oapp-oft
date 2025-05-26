// SPDX-License-Identifier: Apache-2.0
use crate::*;
use crate::msg_codec::GovernanceMessage;
use oapp::endpoint_cpi::{get_accounts_for_clear, LzAccount};
use oapp::{endpoint::ID as ENDPOINT_ID, LzReceiveParams};
use solana_program::address_lookup_table::state::AddressLookupTable;

#[derive(AnchorSerialize, AnchorDeserialize)]
pub enum Instruction {
    LzReceive {
        // The list of accounts needed for lz_receive       
        accounts: Vec<ALTAccountMeta>,     
        // Optional destination EID for ABA messaging pattern
        sending_to: Option<u32>,
    },
    // Arbitrary custom instruction
    Standard {
        program_id: AddressOrAltIndex,
        accounts: Vec<ALTAccountMeta>,
        data: Vec<u8>,
        sending_to: Option<u32>,
    }
}

#[derive(Accounts)]
pub struct LzReceiveTypesV2<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,

    pub lookup_table: AccountInfo<'info>,
}

/// Account metadata returned by `lz_receive_types_v2`.
/// Used by the Executor to invoke `lz_receive`.
#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct ALTAccountMeta {
    // The account address (direct or ALT-based)
    pub pubkey: AddressOrAltIndex,
    // Whether the account should be writable       
    pub is_writable: bool,      
}

/// Output of the `lz_receive_types_v2` instruction.
/// Includes account information and optional intent to send a new cross-chain message.
#[derive(AnchorSerialize, AnchorDeserialize)]
pub struct LzReceiveTypesV2Result {
    // ALTs required for this execution context
    pub alts: Vec<Pubkey>,       
    // The list of instructions required for LzReceive
    // One of them should be LzReceive instruction
    pub instructions: Vec<Instruction>,
}

impl LzReceiveTypesV2<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypesV2>,
        params: &LzReceiveParams,
    ) -> Result<LzReceiveTypesV2Result> {
        let lookup_table = &ctx.accounts.lookup_table;
        let alt_addresses =
            AddressLookupTable::deserialize(*lookup_table.try_borrow_data().unwrap())
                .unwrap()
                .addresses
                .to_vec();

        let governance = ctx.accounts.governance.key();

        // The second account is the remote account, we find it by the params.src_eid.
        let seeds = [
            REMOTE_SEED,
            &governance.to_bytes(),
            &params.src_eid.to_be_bytes(),
        ];
        let (remote, _) = Pubkey::find_program_address(&seeds, ctx.program_id);
        let (cpi_authority, _) = Pubkey::find_program_address(&[CPI_AUTHORITY_SEED, &governance.to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()], ctx.program_id);
        let (cpi_authority_config, _) = Pubkey::find_program_address(&[CPI_AUTHORITY_CONFIG_SEED, &governance.to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()], ctx.program_id);

        let governance_message: GovernanceMessage = GovernanceMessage::from_bytes(&params.message)?;

        // accounts 0..6 (first 7 accounts)
        let mut accounts = vec![
            // payer
            LzAccount {
                pubkey: Pubkey::default(),
                is_signer: true,
                is_writable: true,
            },
            // governance
            LzAccount {
                pubkey: governance,
                is_signer: false,
                is_writable: true,
            },
            // remote
            LzAccount {
                pubkey: remote,
                is_signer: false,
                is_writable: false,
            },
            // cpi authority
            LzAccount {
                pubkey: cpi_authority,
                is_signer: false,
                is_writable: true,
            },
            // cpi authority config
            LzAccount {
                pubkey: cpi_authority_config,
                is_signer: false,
                is_writable: true,
            },
            // program
            LzAccount {
                pubkey: governance_message.program_id,
                is_signer: false,
                is_writable: false,
            },
            // system program
            LzAccount {
                pubkey: solana_program::system_program::id(),
                is_signer: false,
                is_writable: false,
            },
        ];

        // accounts 7..14 (8 accounts, last one #15)
        // Endpoint Clear instruction accounts
        let accounts_for_clear = get_accounts_for_clear(
            ENDPOINT_ID,
            &governance,
            params.src_eid,
            &params.sender,
            params.nonce,
        );
        accounts.extend(accounts_for_clear);

        // accounts 15..
        // Governance message instruction accounts
        accounts.extend(
            governance_message
                .accounts
                .iter()
                .map(|acc| LzAccount {
                    pubkey: if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                        cpi_authority
                    } else if acc.pubkey == PAYER_PLACEHOLDER {
                        Pubkey::default()
                    } else {
                        acc.pubkey
                    },
                    is_signer: false,
                    is_writable: acc.is_writable,
                }),
        );

        // Convert LzAccount to ALTAccountMeta, using ALT index when possible
        let accounts: Vec<ALTAccountMeta> = accounts
            .iter()
            .map(|account| {
                // Try to find the account in the ALT
                let alt_index = alt_addresses
                    .iter()
                    .position(|&alt_addr| alt_addr.to_bytes() == account.pubkey.to_bytes());

                match alt_index {
                    Some(index) => {
                        ALTAccountMeta {
                            pubkey: AddressOrAltIndex::AltIndex(0, index as u8),
                            is_writable: account.is_writable,
                        }
                    }
                    None => {
                        ALTAccountMeta {
                            pubkey: AddressOrAltIndex::Address(account.pubkey),
                            is_writable: account.is_writable,
                        }
                    }
                }
            })
            .collect();

        let result = LzReceiveTypesV2Result {
            alts: vec![ctx.accounts.lookup_table.key()],
            instructions: vec![Instruction::LzReceive {
                accounts,
                sending_to: None,
            }],
        };
        Ok(result)
    }
}
