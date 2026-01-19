//! Transfer Lamports using zero_cu API
//!
//! Transfers lamports from source to destination account.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// ============================================================================
// Accounts
// ============================================================================

const TransferAccounts = struct {
    /// Source account (must be signer, writable)
    source: zero.Signer(0),
    /// Destination account (writable)
    destination: zero.Mut(0),
};

// ============================================================================
// Arguments
// ============================================================================

const TransferArgs = struct {
    amount: u64,
};

// ============================================================================
// Handler
// ============================================================================

pub fn transfer(ctx: zero.Ctx(TransferAccounts)) !void {
    const args = ctx.args(TransferArgs);
    
    // Direct lamport transfer (no CPI needed for program-owned accounts)
    const from_lamports = ctx.accounts.source.lamports();
    const to_lamports = ctx.accounts.destination.lamports();
    
    if (from_lamports.* < args.amount) {
        return error.InsufficientFunds;
    }
    
    from_lamports.* -= args.amount;
    to_lamports.* += args.amount;
}

// ============================================================================
// Program Entry
// ============================================================================

comptime {
    zero.entry(TransferAccounts, "transfer", transfer);
}
