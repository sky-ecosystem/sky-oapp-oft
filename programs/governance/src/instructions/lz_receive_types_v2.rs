// SPDX-License-Identifier: Apache-2.0
use crate::*;
use crate::msg_codec::GovernanceMessage;
use crate::libs::oapp::{build_alt_address_map, get_accounts_for_clear, to_address_locator, AccountMetaRef, AddressLocator, LzInstruction, LzReceiveTypesV2Result};
use oapp::{endpoint::ID as ENDPOINT_ID, LzReceiveParams};

#[derive(Accounts)]
pub struct LzReceiveTypesV2<'info> {
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,
}

impl LzReceiveTypesV2<'_> {
    pub fn apply(
        ctx: &Context<LzReceiveTypesV2>,
        params: &LzReceiveParams,
    ) -> Result<LzReceiveTypesV2Result> {
        // Build address lookup table mapping from remaining_accounts
        // This enables efficient account referencing via ALT indices
        let alt_address_map = build_alt_address_map(&ctx.remaining_accounts)?;
        let alts: Vec<Pubkey> = ctx.remaining_accounts.iter().map(|alt| alt.key()).collect();

        let governance = ctx.accounts.governance.key();
        let (remote, _) = Pubkey::find_program_address(&[REMOTE_SEED, &governance.to_bytes(), &params.src_eid.to_be_bytes()], ctx.program_id);
        let (cpi_authority, _) = Pubkey::find_program_address(&[CPI_AUTHORITY_SEED, &governance.to_bytes(), &GovernanceMessage::decode_origin_caller(&params.message).unwrap()], ctx.program_id);

        let governance_message: GovernanceMessage = GovernanceMessage::from_bytes(&params.message)?;

        // accounts 0..6 (first 7 accounts)
        let mut accounts = vec![
            // payer
            AccountMetaRef {
                pubkey: AddressLocator::Payer,
                is_writable: true,
            },
            // governance
            AccountMetaRef {
                pubkey: to_address_locator(&alt_address_map, governance),
                is_writable: true,
            },
            // remote
            AccountMetaRef {
                pubkey: to_address_locator(&alt_address_map, remote),
                is_writable: false,
            },
            // cpi authority
            AccountMetaRef {
                pubkey: to_address_locator(&alt_address_map, cpi_authority),
                is_writable: true,
            },
            // program
            AccountMetaRef {
                pubkey: to_address_locator(&alt_address_map, governance_message.program_id),
                is_writable: false,
            },
        ];

        // accounts 7..14 (8 accounts, last one #15)
        // Endpoint Clear instruction accounts
        let accounts_for_clear = get_accounts_for_clear(
            &alt_address_map,
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
                .map(|acc| AccountMetaRef {
                    pubkey: to_address_locator(&alt_address_map, if acc.pubkey == CPI_AUTHORITY_PLACEHOLDER {
                        cpi_authority
                    } else {
                        acc.pubkey
                    }),
                    is_writable: acc.is_writable,
                }),
        );

        Ok(LzReceiveTypesV2Result {
            alts,
            instructions: vec![LzInstruction::LzReceive {
                accounts,
            }],
        })
    }
}
