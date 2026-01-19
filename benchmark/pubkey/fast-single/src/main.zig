//! Fast Anchor API - Single Instruction
//!
//! Demonstrates anchor.fast API with Anchor-style patterns
//! and ZeroCU performance (5 CU).

const anchor = @import("sol_anchor_zig");
const fast = anchor.fast;

// ============================================================================
// Account Definition (Anchor-style)
// ============================================================================

const CheckAccounts = struct {
    target: fast.RawAccountReadonly(1), // 1 byte readonly account
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    /// Check if account id equals owner id (same as rosetta)
    pub fn check(ctx: fast.Context(CheckAccounts)) !void {
        const target = ctx.accounts.target;
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Export (5 CU)
// ============================================================================

comptime {
    fast.exportSingle(CheckAccounts, "check", Program.check);
}
