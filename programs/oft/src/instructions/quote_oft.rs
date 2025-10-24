use crate::*;
use anchor_spl::token_interface::Mint;

#[derive(Accounts)]
#[instruction(params: QuoteOFTParams)]
pub struct QuoteOFT<'info> {
    #[account(
        seeds = [OFT_SEED, oft_store.token_escrow.as_ref()],
        bump = oft_store.bump
    )]
    pub oft_store: Account<'info, OFTStore>,
    #[account(
        seeds = [
            PEER_SEED,
            oft_store.key().as_ref(),
            &params.dst_eid.to_be_bytes()
        ],
        bump = peer.bump
    )]
    pub peer: Account<'info, PeerConfig>,
    #[account(address = oft_store.token_mint)]
    pub token_mint: InterfaceAccount<'info, Mint>,
}

impl QuoteOFT<'_> {
    pub fn apply(ctx: &Context<QuoteOFT>, params: &QuoteOFTParams) -> Result<QuoteOFTResult> {
        require!(!ctx.accounts.oft_store.paused, OFTError::Paused);

        let (amount_sent_ld, amount_received_ld, oft_fee_ld) = compute_fee_and_adjust_amount(
            params.amount_ld,
            &ctx.accounts.oft_store,
            &ctx.accounts.token_mint,
            ctx.accounts.peer.fee_bps,
        )?;
        require!(amount_received_ld >= params.min_amount_ld, OFTError::SlippageExceeded);

        let max_amount_ld = if let Some(rate_limiter) = &ctx.accounts.peer.outbound_rate_limiter {
            rate_limiter.clone().fetch_available_capacity()?
        } else {
            0
        };

        let oft_limits = OFTLimits { 
            min_amount_ld: 0, 
            max_amount_ld 
        };

        let mut oft_fee_details = if amount_received_ld + oft_fee_ld < amount_sent_ld {
            vec![OFTFeeDetail {
                fee_amount_ld: amount_sent_ld - oft_fee_ld - amount_received_ld,
                description: "Token2022 Transfer Fee".to_string(),
            }]
        } else {
            vec![]
        };
        // cross chain fee
        if oft_fee_ld > 0 {           
            // Nuance: Native (mint-and-burn) with fee-on-transfer tokens may result
            // in the escrow receiving slightly less than the intended fee due to
            // transfer fees; Adapter (escrow) computes the fee on post-transfer
            // amounts so intended ≈ actual. See compute_fee_and_adjust_amount docs.
            oft_fee_details.push(OFTFeeDetail {
                fee_amount_ld: oft_fee_ld,
                description: "Cross Chain Fee".to_string(),
            });
        }
        let oft_receipt = OFTReceipt { amount_sent_ld, amount_received_ld };
        Ok(QuoteOFTResult { oft_limits, oft_fee_details, oft_receipt })
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteOFTParams {
    pub dst_eid: u32,
    pub to: [u8; 32],
    pub amount_ld: u64,
    pub min_amount_ld: u64,
    pub options: Vec<u8>,
    pub compose_msg: Option<Vec<u8>>,
    pub pay_in_lz_token: bool,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct QuoteOFTResult {
    pub oft_limits: OFTLimits,
    pub oft_fee_details: Vec<OFTFeeDetail>,
    pub oft_receipt: OFTReceipt,
}

/// Details about a specific fee component in OFT operations.
/// 
/// Note: For Native (mint-and-burn) type OFTs with fee-on-transfer tokens, the
/// actual received fee in the escrow may be less than `fee_amount_ld` due to
/// transfer fees applied during the fee transfer operation. For Adapter
/// (escrow) type OFTs, `fee_amount_ld` reflects both the intended and actual
/// received fee since the fee is calculated on the post-transfer-fee amount.
#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTFeeDetail {
    pub fee_amount_ld: u64,
    pub description: String,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTReceipt {
    pub amount_sent_ld: u64,
    pub amount_received_ld: u64,
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct OFTLimits {
    pub min_amount_ld: u64,
    pub max_amount_ld: u64,
}
