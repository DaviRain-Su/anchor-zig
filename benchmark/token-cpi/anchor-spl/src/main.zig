//! Token CPI Example using anchor.spl.token
//!
//! This demonstrates the CORRECT usage of anchor.spl.token module:
//! - Calling the real SPL Token Program via CPI
//! - Using Anchor-style account definitions
//! - Type-safe token account access
//!
//! This is similar to how you would use `anchor_spl::token` in Rust Anchor.

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const spl = anchor.spl;
const sol = anchor.sdk;

const PublicKey = sol.public_key.PublicKey;
const Context = sol.context.Context;

// ============================================================================
// Program Instructions
// ============================================================================

// Discriminators (8-byte Anchor style)
const TRANSFER_DISC: u64 = 0xf3a8d8a012b0e71c; // anchor discriminator for "transfer"
const MINT_TO_DISC: u64 = 0x6e3f8f4a2b1c0d9e;  // anchor discriminator for "mint_to"  
const BURN_DISC: u64 = 0x1a2b3c4d5e6f7890;     // anchor discriminator for "burn"
const CLOSE_DISC: u64 = 0x0987654321fedcba;    // anchor discriminator for "close"

// ============================================================================
// Handlers - Using spl.token CPI helpers
// ============================================================================

/// Transfer tokens using spl.token.transfer() CPI
fn handleTransfer(accounts: []const sol.account.Account, data: []const u8) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    if (data.len < 16) return error.InvalidInstructionData; // 8 disc + 8 amount
    
    const source = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];
    // accounts[3] is token_program
    
    const amount = std.mem.readInt(u64, data[8..16], .little);
    
    // Use anchor.spl.token CPI helper!
    try spl.token.transfer(source, destination, authority, amount);
}

/// Mint tokens using spl.token.mintTo() CPI
fn handleMintTo(accounts: []const sol.account.Account, data: []const u8) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    if (data.len < 16) return error.InvalidInstructionData;
    
    const mint = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];
    // accounts[3] is token_program
    
    const amount = std.mem.readInt(u64, data[8..16], .little);
    
    // Use anchor.spl.token CPI helper!
    try spl.token.mintTo(mint, destination, authority, amount);
}

/// Burn tokens using spl.token.burn() CPI
fn handleBurn(accounts: []const sol.account.Account, data: []const u8) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    if (data.len < 16) return error.InvalidInstructionData;
    
    const source = accounts[0];
    const mint = accounts[1];
    const authority = accounts[2];
    // accounts[3] is token_program
    
    const amount = std.mem.readInt(u64, data[8..16], .little);
    
    // Use anchor.spl.token CPI helper!
    try spl.token.burn(source, mint, authority, amount);
}

/// Close token account using spl.token.close() CPI
fn handleClose(accounts: []const sol.account.Account) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    
    const account_to_close = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];
    // accounts[3] is token_program
    
    // Use anchor.spl.token CPI helper!
    try spl.token.close(account_to_close, destination, authority);
}

// ============================================================================
// Entrypoint
// ============================================================================

export fn entrypoint(input: [*]u8) u64 {
    const context = Context.load(input) catch return 1;
    if (context.data.len < 8) return 1;
    
    const discriminant = std.mem.readInt(u64, context.data[0..8], .little);
    const accounts = context.accounts[0..context.num_accounts];
    
    switch (discriminant) {
        TRANSFER_DISC => handleTransfer(accounts, context.data) catch return 1,
        MINT_TO_DISC => handleMintTo(accounts, context.data) catch return 1,
        BURN_DISC => handleBurn(accounts, context.data) catch return 1,
        CLOSE_DISC => handleClose(accounts) catch return 1,
        else => return 1,
    }
    
    return 0;
}
