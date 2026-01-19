//! ZeroCU Multi-Instruction
//!
//! Same logic as rosetta but with multiple instructions.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Definition
// ============================================================================

const ProgramAccounts = struct {
    target: zero.Readonly(1),
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    /// Check if account id equals owner id
    pub fn check(ctx: zero.Ctx(ProgramAccounts)) !void {
        const target = ctx.accounts.target;
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }

    /// Alternative: verify owner is not zero
    pub fn verify(ctx: zero.Ctx(ProgramAccounts)) !void {
        const target = ctx.accounts.target;
        const zero_key = anchor.sdk.PublicKey.default();
        if (target.ownerId().equals(zero_key)) {
            return error.InvalidOwner;
        }
    }
};

// ============================================================================
// Multi-instruction export
// ============================================================================

comptime {
    zero.multi(ProgramAccounts, .{
        zero.inst("check", Program.check),
        zero.inst("verify", Program.verify),
    });
}
