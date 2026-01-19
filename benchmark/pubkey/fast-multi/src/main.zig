//! Fast Anchor API - Multi Instruction
//!
//! Demonstrates anchor.fast API with multiple instructions
//! and ZeroCU performance (7 CU).

const anchor = @import("sol_anchor_zig");
const fast = anchor.fast;

// ============================================================================
// Account Definition (Anchor-style)
// ============================================================================

const ProgramAccounts = struct {
    target: fast.RawAccountReadonly(1),
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    /// Check if account id equals owner id
    pub fn check(ctx: fast.Context(ProgramAccounts)) !void {
        const target = ctx.accounts.target;
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }

    /// Verify owner is not zero
    pub fn verify(ctx: fast.Context(ProgramAccounts)) !void {
        const target = ctx.accounts.target;
        const zero_key = anchor.sdk.PublicKey.default();
        if (target.ownerId().equals(zero_key)) {
            return error.InvalidOwner;
        }
    }
};

// ============================================================================
// Export (7 CU per instruction)
// ============================================================================

comptime {
    fast.exportProgram(ProgramAccounts, .{
        fast.instruction("check", Program.check),
        fast.instruction("verify", Program.verify),
    });
}
