//! Transfer Lamports using zero_cu program() + ixValidated()
//!
//! Recommended pattern for production programs.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// Program ID for owner constraint
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("TransferLamports111111111111111111111111111");

// ============================================================================
// Accounts with constraints
// ============================================================================

const TransferAccounts = struct {
    /// Source account (must be signer, program-owned)
    source: zero.Account(struct {}, .{
        .signer = true,
        .writable = true,
        .owner = PROGRAM_ID,
    }),
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
    const accs = ctx.accounts();
    
    const from_lamports = accs.source.lamports();
    const to_lamports = accs.destination.lamports();
    
    if (from_lamports.* < args.amount) {
        return error.InsufficientFunds;
    }
    
    from_lamports.* -= args.amount;
    to_lamports.* += args.amount;
}

// ============================================================================
// Program Entry - Recommended Pattern
// ============================================================================

comptime {
    zero.program(.{
        zero.ixValidated("transfer", TransferAccounts, transfer),
    });
}
