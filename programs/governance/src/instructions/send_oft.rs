use crate::*;
use anchor_lang::prelude::*;
use anchor_spl::token_interface::{self, Mint, TokenAccount, TokenInterface, TransferChecked};
use oft::instructions::send::SendParams;
use solana_program::sysvar::instructions::{
    load_current_index_checked, load_instruction_at_checked,
};

pub const OFT_PROGRAM_ID: Pubkey =
    solana_program::pubkey!("E2R6qMMzLBjCwXs66MPEg2zKfpt5AMxWNgSULsLYfPS2");
pub const OFT_SEND_PARAMS_DISCRIMINATOR: [u8; 8] = [102, 251, 20, 187, 65, 75, 12, 69];

#[derive(Accounts)]
#[instruction(params: SendOFTParams)]
pub struct SendOFT<'info> {
    #[account(address = governance.admin)]
    pub admin: Signer<'info>,
    #[account(seeds = [GOVERNANCE_SEED, &governance.id.to_be_bytes()], bump = governance.bump)]
    pub governance: Account<'info, Governance>,
    #[account(
        mut,
        token::authority = governance,
        token::mint = token_mint,
        token::token_program = token_program
    )]
    pub token_source: InterfaceAccount<'info, TokenAccount>,
    #[account(
        mut,
        token::authority = admin,
        token::mint = token_mint,
        token::token_program = token_program
    )]
    pub token_dest: InterfaceAccount<'info, TokenAccount>,
    #[account(mint::token_program = token_program)]
    pub token_mint: InterfaceAccount<'info, Mint>,
    pub token_program: Interface<'info, TokenInterface>,
    /// Instruction reflection account (special sysvar)
    pub instruction_acc: AccountInfo<'info>,
}

impl SendOFT<'_> {
    pub fn apply(ctx: &mut Context<SendOFT>, params: &SendOFTParams) -> Result<()> {
        // 1. Check this instruction is at the first instruction of the transaction
        let current_instruction = load_current_index_checked(&ctx.accounts.instruction_acc)?;
        require!(
            current_instruction == 0,
            GovernanceError::InvalidInstruction
        );
        // 2. Check the 2nd instruction is the OFT send instruction
        let sec_ix = load_instruction_at_checked(1, &ctx.accounts.instruction_acc)?;
        require!(
            sec_ix.program_id == OFT_PROGRAM_ID,
            GovernanceError::InvalidInstruction
        );

        // 3. Decode the OFT send instruction data and assert the amount
        require!(
            &sec_ix.data[..8] == OFT_SEND_PARAMS_DISCRIMINATOR,
            GovernanceError::InvalidInstruction
        );
        let send_ix = SendParams::deserialize(&mut &sec_ix.data[8..])?;
        require!(
            send_ix.amount_ld == params.amount,
            GovernanceError::InvalidInstruction
        );
        // 4. check the accounts of OFT Send instruction
        // the signer of OFT Send instruction is the admin
        require!(
            sec_ix.accounts[0].pubkey == ctx.accounts.admin.key(),
            GovernanceError::InvalidInstruction
        );
        // the token source account of OFT Send instruction is the token destination of this instruction
        require!(
            sec_ix.accounts[3].pubkey == ctx.accounts.token_dest.key(),
            GovernanceError::InvalidInstruction
        );
        // check the token mint of OFT Send instruction is the token mint of this instruction
        require!(
            sec_ix.accounts[5].pubkey == ctx.accounts.token_mint.key(),
            GovernanceError::InvalidInstruction
        );

        // 5. transfer the token to the token destination, where the token will be burned or locked in the OFT Send instruction
        token_interface::transfer_checked(
            CpiContext::new(
                ctx.accounts.token_program.to_account_info(),
                TransferChecked {
                    from: ctx.accounts.token_source.to_account_info(),
                    mint: ctx.accounts.token_mint.to_account_info(),
                    to: ctx.accounts.token_dest.to_account_info(),
                    authority: ctx.accounts.governance.to_account_info(),
                },
            )
            .with_signer(&[&[
                GOVERNANCE_SEED,
                &ctx.accounts.governance.id.to_be_bytes(),
                &[ctx.accounts.governance.bump],
            ]]),
            params.amount,
            ctx.accounts.token_mint.decimals,
        )?;

        Ok(())
    }
}

#[derive(Clone, AnchorSerialize, AnchorDeserialize)]
pub struct SendOFTParams {
    pub amount: u64,
}
