//! ZeroCU Single Instruction Example
//!
//! Demonstrates the clean zero_cu API for single-instruction programs.
//! Result: 5 CU (same as raw Zig, 3x faster than rosetta's 15 CU)

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Definition
// ============================================================================

const CheckAccounts = struct {
    target: zero.Readonly(1), // Account with 1 byte data
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "PubkeyComp111111111111111111111111111111111"
    );

    /// Check if account id equals owner id
    pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
        const target = ctx.accounts.target;

        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Single-line entrypoint export (5 CU)
// ============================================================================

comptime {
    zero.entry(CheckAccounts, "check", Program.check);
}
