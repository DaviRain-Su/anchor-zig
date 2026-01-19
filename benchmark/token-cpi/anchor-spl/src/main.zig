//! Token CPI Example using anchor-zig framework
//!
//! This demonstrates the FULL Anchor-style API for CPI:
//! - Declarative account definitions with spl.token types
//! - zero.program() for instruction dispatch
//! - spl.token CPI helpers for calling SPL Token Program
//!
//! Similar to Rust Anchor's usage:
//! ```rust
//! use anchor_lang::prelude::*;
//! use anchor_spl::token::{self, Token, TokenAccount, Transfer};
//!
//! #[derive(Accounts)]
//! pub struct TransferTokens<'info> {
//!     #[account(mut)]
//!     pub source: Account<'info, TokenAccount>,
//!     #[account(mut)]  
//!     pub destination: Account<'info, TokenAccount>,
//!     pub authority: Signer<'info>,
//!     pub token_program: Program<'info, Token>,
//! }
//!
//! pub fn transfer_tokens(ctx: Context<TransferTokens>, amount: u64) -> Result<()> {
//!     token::transfer(
//!         CpiContext::new(
//!             ctx.accounts.token_program.to_account_info(),
//!             Transfer {
//!                 from: ctx.accounts.source.to_account_info(),
//!                 to: ctx.accounts.destination.to_account_info(),
//!                 authority: ctx.accounts.authority.to_account_info(),
//!             },
//!         ),
//!         amount,
//!     )
//! }
//! ```

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const spl = anchor.spl;
const sol = anchor.sdk;

// ============================================================================
// Account Definitions - Anchor Style with SPL Token types!
// ============================================================================

/// Transfer instruction accounts
/// Similar to Rust: #[derive(Accounts)] pub struct Transfer<'info>
const TransferAccounts = struct {
    /// Source token account (writable)
    /// #[account(mut)]
    source: spl.token.TokenAccount(.{ .mut = true }),
    
    /// Destination token account (writable)
    /// #[account(mut)]
    destination: spl.token.TokenAccount(.{ .mut = true }),
    
    /// Authority/owner of source account (signer)
    authority: zero.Signer(0),
    
    /// SPL Token Program
    /// Program<'info, Token>
    token_program: spl.token.Program,
};

/// MintTo instruction accounts
const MintToAccounts = struct {
    /// The mint (writable)
    mint: spl.token.MintAccount(.{ .mut = true }),
    
    /// Destination token account (writable)
    destination: spl.token.TokenAccount(.{ .mut = true }),
    
    /// Mint authority (signer)
    authority: zero.Signer(0),
    
    /// SPL Token Program
    token_program: spl.token.Program,
};

/// Burn instruction accounts  
const BurnAccounts = struct {
    /// Source token account (writable)
    source: spl.token.TokenAccount(.{ .mut = true }),
    
    /// The mint (writable)
    mint: spl.token.MintAccount(.{ .mut = true }),
    
    /// Authority (signer)
    authority: zero.Signer(0),
    
    /// SPL Token Program
    token_program: spl.token.Program,
};

/// CloseAccount instruction accounts
const CloseAccounts = struct {
    /// Account to close (writable)
    account: spl.token.TokenAccount(.{ .mut = true }),
    
    /// Destination for rent lamports (writable)
    destination: zero.Mut(0),
    
    /// Authority (signer)
    authority: zero.Signer(0),
    
    /// SPL Token Program
    token_program: spl.token.Program,
};

// ============================================================================
// Instruction Arguments
// ============================================================================

const AmountArgs = extern struct {
    amount: u64,
};

// ============================================================================
// Handlers - Clean Anchor-style using spl.token CPI!
// ============================================================================

/// Transfer tokens via CPI to SPL Token Program
fn transfer(ctx: *zero.ProgramContext(TransferAccounts)) !void {
    // Get typed arguments (skip 8-byte discriminator automatically)
    const args = ctx.args(AmountArgs);
    
    // Get accounts accessor
    const accs = ctx.accounts();
    
    // Use anchor.spl.token CPI helper!
    // This calls the real SPL Token Program
    try spl.token.transfer(
        accs.source.info(),
        accs.destination.info(),
        accs.authority.info(),
        args.amount,
    );
}

/// Mint tokens via CPI to SPL Token Program
fn mintTo(ctx: *zero.ProgramContext(MintToAccounts)) !void {
    const args = ctx.args(AmountArgs);
    const accs = ctx.accounts();
    
    try spl.token.mintTo(
        accs.mint.info(),
        accs.destination.info(),
        accs.authority.info(),
        args.amount,
    );
}

/// Burn tokens via CPI to SPL Token Program
fn burn(ctx: *zero.ProgramContext(BurnAccounts)) !void {
    const args = ctx.args(AmountArgs);
    const accs = ctx.accounts();
    
    try spl.token.burn(
        accs.source.info(),
        accs.mint.info(),
        accs.authority.info(),
        args.amount,
    );
}

/// Close token account via CPI to SPL Token Program
fn close(ctx: *zero.ProgramContext(CloseAccounts)) !void {
    const accs = ctx.accounts();
    
    try spl.token.close(
        accs.account.info(),
        accs.destination.info(),
        accs.authority.info(),
    );
}

// ============================================================================
// Program Entry - Using zero.program() API!
// ============================================================================

comptime {
    // Export program with multiple instructions, each with its own account layout
    // Uses dynamic parsing (Context.load) because we have Program type
    zero.program(.{
        zero.ix("transfer", TransferAccounts, transfer),
        zero.ix("mint_to", MintToAccounts, mintTo),
        zero.ix("burn", BurnAccounts, burn),
        zero.ix("close", CloseAccounts, close),
    });
}
