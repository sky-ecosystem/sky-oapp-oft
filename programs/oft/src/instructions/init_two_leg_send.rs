use crate::*;
use anchor_lang::solana_program::keccak::hashv;
use anchor_spl::token_interface::{
    self, Burn, Mint, TokenAccount, TokenInterface, TransferChecked,
};

// #[event_cpi]
#[derive(Accounts)]
#[instruction(params: SendParams)]
pub struct InitTwoLegSend<'info> {
    pub signer: Signer<'info>,
    #[account(
        mut,
        seeds = [
            PEER_SEED,
            oft_store.key().as_ref(),
            &params.dst_eid.to_be_bytes()
        ],
        bump = peer.bump
    )]
    pub peer: Account<'info, PeerConfig>,
    #[account(
        mut,
        seeds = [OFT_SEED, oft_store.token_escrow.as_ref()],
        bump = oft_store.bump
    )]
    pub oft_store: Account<'info, OFTStore>,
    #[account(
        mut,
        token::authority = signer,
        token::mint = token_mint,
        token::token_program = token_program
    )]
    pub token_source: InterfaceAccount<'info, TokenAccount>,
    #[account(
        mut,
        address = oft_store.token_escrow,
        token::authority = oft_store.key(),
        token::mint = token_mint,
        token::token_program = token_program
    )]
    pub token_escrow: InterfaceAccount<'info, TokenAccount>,
    #[account(
        mut,
        address = oft_store.token_mint,
        mint::token_program = token_program
    )]
    pub token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    #[account(
        mut,
        seeds = [TWO_LEG_SEND_PENDING_MESSAGE_STORE_SEED, oft_store.key().as_ref(), signer.key().as_ref()],
        bump
    )]
    pub two_leg_send_pending_message_store: Account<'info, TwoLegSendPendingMessageStore>,
}

impl InitTwoLegSend<'_> {
    pub fn apply(ctx: &mut Context<InitTwoLegSend>, params: &SendParams) -> Result<()> {
        require!(!ctx.accounts.oft_store.paused, OFTError::Paused);
        require!(
            ctx.accounts.two_leg_send_pending_message_store.queue.len()
                < MAX_PENDING_TWO_LEG_SEND_MESSAGES,
            OFTError::MaxPendingTwoLegSendMessagesExceeded
        );

        let (amount_sent_ld, amount_received_ld, oft_fee_ld) = compute_fee_and_adjust_amount(
            params.amount_ld,
            &ctx.accounts.oft_store,
            &ctx.accounts.token_mint,
            ctx.accounts.peer.fee_bps,
        )?;
        require!(
            amount_received_ld >= params.min_amount_ld,
            OFTError::SlippageExceeded
        );

        if ctx.accounts.oft_store.oft_type == OFTType::Adapter {
            // transfer all tokens to escrow with fee
            ctx.accounts.oft_store.tvl_ld += amount_received_ld;
            token_interface::transfer_checked(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    TransferChecked {
                        from: ctx.accounts.token_source.to_account_info(),
                        mint: ctx.accounts.token_mint.to_account_info(),
                        to: ctx.accounts.token_escrow.to_account_info(),
                        authority: ctx.accounts.signer.to_account_info(),
                    },
                ),
                amount_sent_ld,
                ctx.accounts.token_mint.decimals,
            )?;
        } else {
            // Native type
            // burn
            token_interface::burn(
                CpiContext::new(
                    ctx.accounts.token_program.to_account_info(),
                    Burn {
                        mint: ctx.accounts.token_mint.to_account_info(),
                        from: ctx.accounts.token_source.to_account_info(),
                        authority: ctx.accounts.signer.to_account_info(),
                    },
                ),
                amount_sent_ld - oft_fee_ld,
            )?;

            // transfer fee to escrow
            if oft_fee_ld > 0 {
                token_interface::transfer_checked(
                    CpiContext::new(
                        ctx.accounts.token_program.to_account_info(),
                        TransferChecked {
                            from: ctx.accounts.token_source.to_account_info(),
                            mint: ctx.accounts.token_mint.to_account_info(),
                            to: ctx.accounts.token_escrow.to_account_info(),
                            authority: ctx.accounts.signer.to_account_info(),
                        },
                    ),
                    oft_fee_ld,
                    ctx.accounts.token_mint.decimals,
                )?;
            }
        }

        let send_params_hash = hash_send_params(params);
        let new_nonce = ctx
            .accounts
            .two_leg_send_pending_message_store
            .last_nonce_used
            + 1;
        ctx.accounts
            .two_leg_send_pending_message_store
            .queue
            .push(TwoLegSendPendingMessage {
                nonce: new_nonce,
                send_params_hash,
            });
        ctx.accounts
            .two_leg_send_pending_message_store
            .last_nonce_used = new_nonce;

        Ok(())
    }
}

fn hash_send_params(params: &SendParams) -> [u8; 32] {
    let mut writer = Vec::new();
    params.serialize(&mut writer).unwrap();
    hashv(&[&writer]).to_bytes()
}
