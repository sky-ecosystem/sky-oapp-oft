use crate::*;
use anchor_lang::solana_program::keccak::hashv;
use anchor_spl::token_interface::{Mint, TokenAccount, TokenInterface};
use oapp::endpoint::{instructions::SendParams as EndpointSendParams, MessagingReceipt};

#[event_cpi]
#[derive(Accounts)]
#[instruction(params: ExecuteTwoLegSendParams)]
pub struct ExecuteTwoLegSend<'info> {
    pub signer: Signer<'info>,
    #[account(
        mut,
        seeds = [
            PEER_SEED,
            oft_store.key().as_ref(),
            &params.send_params.dst_eid.to_be_bytes()
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
        token::mint = token_mint,
        token::token_program = token_program
    )]
    pub token_source: InterfaceAccount<'info, TokenAccount>,
    #[account(
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
        seeds = [TWO_LEG_SEND_PENDING_MESSAGE_STORE_SEED, oft_store.key().as_ref(), params.sender.as_ref()],
        bump
    )]
    pub two_leg_send_pending_message_store: Account<'info, TwoLegSendPendingMessageStore>,
}

impl ExecuteTwoLegSend<'_> {
    pub fn apply(
        ctx: &mut Context<ExecuteTwoLegSend>,
        params: &ExecuteTwoLegSendParams,
    ) -> Result<(MessagingReceipt, OFTReceipt)> {
        require!(!ctx.accounts.oft_store.paused, OFTError::Paused);

        let msg = ctx
            .accounts
            .two_leg_send_pending_message_store
            .queue
            .iter()
            .find(|msg| msg.nonce == params.nonce)
            .ok_or(OFTError::InvalidTwoLegSendNonce)?;
        let send_params_hash = hash_send_params(&params.send_params);

        require!(
            msg.send_params_hash == send_params_hash,
            OFTError::InvalidTwoLegSendParamsHash
        );

        // Remove the nonce from the pending store
        ctx.accounts
            .two_leg_send_pending_message_store
            .queue
            .retain(|msg| msg.nonce != params.nonce);

        let (amount_sent_ld, amount_received_ld, _oft_fee_ld) = compute_fee_and_adjust_amount(
            params.send_params.amount_ld,
            &ctx.accounts.oft_store,
            &ctx.accounts.token_mint,
            ctx.accounts.peer.fee_bps,
        )?;

        if let Some(rate_limiter) = ctx.accounts.peer.outbound_rate_limiter.as_mut() {
            rate_limiter.try_consume(amount_received_ld)?;
        }
        if let Some(rate_limiter) = ctx.accounts.peer.inbound_rate_limiter.as_mut() {
            rate_limiter.refill(amount_received_ld)?;
        }

        // send message to endpoint
        require!(
            ctx.accounts.oft_store.key() == ctx.remaining_accounts[1].key(),
            OFTError::InvalidSender
        );
        let amount_sd = ctx.accounts.oft_store.ld2sd(amount_received_ld);
        let msg_receipt = oapp::endpoint_cpi::send(
            ctx.accounts.oft_store.endpoint_program,
            ctx.accounts.oft_store.key(),
            ctx.remaining_accounts,
            &[
                OFT_SEED,
                ctx.accounts.token_escrow.key().as_ref(),
                &[ctx.accounts.oft_store.bump],
            ],
            EndpointSendParams {
                dst_eid: params.send_params.dst_eid,
                receiver: ctx.accounts.peer.peer_address,
                message: msg_codec::encode(
                    params.send_params.to,
                    amount_sd,
                    ctx.accounts.signer.key(),
                    &params.send_params.compose_msg,
                ),
                options: ctx.accounts.peer.enforced_options.combine_options(
                    &params.send_params.compose_msg,
                    &params.send_params.options,
                )?,
                native_fee: params.native_fee,
                lz_token_fee: params.lz_token_fee,
            },
        )?;

        emit_cpi!(OFTSent {
            guid: msg_receipt.guid,
            dst_eid: params.send_params.dst_eid,
            from: ctx.accounts.token_source.key(),
            amount_sent_ld,
            amount_received_ld
        });

        Ok((
            msg_receipt,
            OFTReceipt {
                amount_sent_ld,
                amount_received_ld,
            },
        ))
    }
}

fn hash_send_params(params: &SendParams) -> [u8; 32] {
    let mut writer = Vec::new();
    params.serialize(&mut writer).unwrap();
    hashv(&[&writer]).to_bytes()
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct ExecuteTwoLegSendParams {
    sender: Pubkey,
    nonce: u64,
    send_params: SendParams,
    native_fee: u64,
    lz_token_fee: u64,
}

#[test]
fn test_hash_send_params() {
    let send_params = SendParams {
        to: [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8, 4, 166, 226, 121, 143, 66, 199, 243, 201, 114,
            21, 221, 249, 88, 213, 80, 15, 142, 200,
        ],
        options: vec![
            0, 3, 1, 0, 17, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 13, 64
          ],
        compose_msg: None,
        native_fee: 0,
        lz_token_fee: 0,
        amount_ld: 1000,
        min_amount_ld: 1000,
        dst_eid: 40106,
    };
    let send_params_hash = hash_send_params(&send_params);
    msg!("send_params_hash: {:?}", send_params_hash);
}
