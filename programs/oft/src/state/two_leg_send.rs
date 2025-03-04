use crate::*;

pub const MAX_PENDING_TWO_LEG_SEND_MESSAGES: usize = 20;

#[account]
#[derive(InitSpace)]
pub struct TwoLegSendPendingMessage {
    pub nonce: u64,
    pub send_params_hash: [u8; 32],
}

#[account]
#[derive(InitSpace)]
pub struct TwoLegSendPendingMessageStore {
    #[max_len(MAX_PENDING_TWO_LEG_SEND_MESSAGES)]
    pub queue: Vec<TwoLegSendPendingMessage>,
    pub last_nonce_used: u64,
}
