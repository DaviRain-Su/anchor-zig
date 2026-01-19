//! ZeroCU Single Instruction
//!
//! Same logic as solana-program-rosetta/pubkey but with ZeroCU framework.
//! Check if account id equals owner id.
//!
//! Result: 5 CU (zero overhead)

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Definition
// ============================================================================

const CheckAccounts = struct {
    target: zero.Readonly(1), // 1 byte data (same as rosetta test)
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    /// Check if account id equals owner id
    pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
        const target = ctx.accounts.target;
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Single instruction export (5 CU)
// ============================================================================

comptime {
    zero.entry(CheckAccounts, "check", Program.check);
}
