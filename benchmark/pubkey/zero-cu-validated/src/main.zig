//! ZeroCU with Constraint Validation
//!
//! Demonstrates automatic constraint validation.
//! Uses entryValidated() which calls ctx.validate() automatically.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// Program ID (for owner constraint)
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// Account Definition with Constraints
// ============================================================================

const CheckAccounts = struct {
    // Account with owner constraint
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID, // Auto-validated
    }),
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    /// Check with automatic owner validation
    pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
        // ctx.validate() already called by entryValidated
        // Just access the data
        _ = ctx.accounts().target.get().value;
    }
};

// ============================================================================
// Export with auto-validation
// ============================================================================

comptime {
    zero.entryValidated(CheckAccounts, "check", Program.check);
}
