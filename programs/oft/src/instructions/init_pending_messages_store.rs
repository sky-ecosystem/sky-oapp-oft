use crate::*;
use anchor_spl::token_interface::TokenAccount;

#[derive(Accounts)]
#[instruction(params: InitPendingMessagesStoreParams)]
pub struct InitPendingMessagesStore<'info> {
    #[account(mut)]
    pub payer: Signer<'info>,
    #[account(
        seeds = [OFT_SEED, token_escrow.key().as_ref()],
        bump
    )]
    pub oft_store: Account<'info, OFTStore>,
    #[account(
        address = oft_store.token_escrow,
    )]
    pub token_escrow: InterfaceAccount<'info, TokenAccount>,
    #[account(
        init,
        payer = payer,
        space = 8 + TwoLegSendPendingMessageStore::INIT_SPACE,
        seeds = [TWO_LEG_SEND_PENDING_MESSAGE_STORE_SEED, oft_store.key().as_ref(), params.oft_sender.as_ref()],
        bump
    )]
    pub two_leg_send_pending_message_store: Account<'info, TwoLegSendPendingMessageStore>,
    pub system_program: Program<'info, System>,
}

impl InitPendingMessagesStore<'_> {
    pub fn apply(
        _ctx: &mut Context<InitPendingMessagesStore>,
        _params: &InitPendingMessagesStoreParams,
    ) -> Result<()> {
        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct InitPendingMessagesStoreParams {
    pub oft_sender: Pubkey,
}
