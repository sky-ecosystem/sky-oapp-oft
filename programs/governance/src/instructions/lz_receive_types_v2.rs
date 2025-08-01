// SPDX-License-Identifier: Apache-2.0
use crate::*;
use crate::msg_codec::GovernanceMessage;
use oapp::common::{
    compact_accounts_with_alts, AccountMetaRef, AddressLocator, EXECUTION_CONTEXT_VERSION_1,
};
use oapp::lz_receive_types_v2::{
    get_accounts_for_clear, Instruction, LzReceiveTypesV2Result,
};
use oapp::{endpoint::ID as ENDPOINT_ID, LzReceiveParams};

/// LzReceiveTypesV2 instruction implements the V2 framework for resolving account dependencies.
///
/// V2 introduces an extensible and optimized framework addressing V1 limitations by introducing:
/// - Support for multiple ALTs to increase the number of accounts
/// - A compact and flexible account reference model via AddressLocator
/// - Explicit support for multiple EOA signers, enabling dynamic data account initialization
/// - A multi-instruction execution model for complex workflows within a single atomic transaction
///
/// Unlike V1's single-instruction CPI-based execution model, V2 adopts a transaction-based
/// execution model to avoid Solana's CPI depth limitation of 4, making ABA messaging patterns
/// feasible.
#[derive(Accounts)]
pub struct LzReceiveTypesV2<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,
}

impl LzReceiveTypesV2<'_> {
    /// Returns the account dependencies and execution plan for lz_receive
    ///
    /// This instruction is called by the Executor after resolving version and account data
    /// from lz_receive_types_info. It returns a complete execution plan including:
    /// - ALTs required for this execution context (from remaining_accounts)
    /// - List of instructions required for LzReceive (including exactly one LzReceive instruction)
    pub fn apply(
        ctx: &Context<LzReceiveTypesV2>,
        params: &LzReceiveParams,
    ) -> Result<LzReceiveTypesV2Result> {
        let governance = ctx.accounts.governance.key();
        let (remote, _) = Pubkey::find_program_address(&[REMOTE_SEED, &governance.to_bytes(), &params.src_eid.to_be_bytes()], ctx.program_id);

        let governance_message: GovernanceMessage = GovernanceMessage::from_bytes(&params.message)?;

        let (cpi_authority, _) = Pubkey::find_program_address(&[CPI_AUTHORITY_SEED, &governance.to_bytes(), &params.src_eid.to_be_bytes(), &governance_message.origin_caller], ctx.program_id);

        // accounts indexes 0 to 3 inclusive (first 4 accounts)
        let mut accounts = vec![
            // payer
            AccountMetaRef {
                pubkey: AddressLocator::Payer,
                is_writable: true,
            },
            // governance
            AccountMetaRef {
                pubkey: governance.into(),
                is_writable: false,
            },
            // remote
            AccountMetaRef {
                pubkey: remote.into(),
                is_writable: false,
            },
            // cpi authority
            AccountMetaRef {
                pubkey: cpi_authority.into(),
                is_writable: false,
            },
        ];

        // accounts indexes 4 to 11 inclusive (8 accounts, last one #12)
        // Add accounts required for LayerZero's Endpoint clear operation
        // These accounts handle the core message verification and processing
        let accounts_for_clear: Vec<AccountMetaRef> = get_accounts_for_clear(
            ENDPOINT_ID,
            &governance,
            params.src_eid,
            &params.sender,
            params.nonce,
        );
        accounts.extend(accounts_for_clear);

        // accounts indexes starting from 12
        // custom CPI accounts for each instruction including program accounts
        for instruction in governance_message.instructions {
            // Governance message instruction program account
            accounts.push(AccountMetaRef {
                pubkey: instruction.program_id.into(),
                is_writable: false,
            });
            
            // Governance message instruction accounts
            accounts.extend(
                instruction
                    .accounts
                    .iter()
                    .map(|acc| AccountMetaRef {
                        pubkey: if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                            cpi_authority.into()
                        } else if acc.pubkey == PAYER_PLACEHOLDER {
                            AddressLocator::Payer
                        } else if acc.pubkey == CONTEXT_PLACEHOLDER {
                            AddressLocator::Context
                        } else {
                            acc.pubkey.into()
                        },
                        is_writable: acc.is_writable,
                    }),
            );
        }

        // Return the complete execution plan with ALTs and instructions
        Ok(LzReceiveTypesV2Result {
            context_version: EXECUTION_CONTEXT_VERSION_1,
            alts: ctx.remaining_accounts.iter().map(|alt| alt.key()).collect(),
            instructions: vec![
                // Main LzReceive instruction - processes the cross-chain message
                Instruction::LzReceive {
                    accounts: compact_accounts_with_alts(&ctx.remaining_accounts, accounts)?,
                },
            ],
        })
    }
}
