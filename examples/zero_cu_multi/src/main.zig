//! ZeroCU Multi-Instruction Example
//!
//! Demonstrates the zero_cu API for multi-instruction programs.
//! Result: 7 CU per instruction

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Shared Account Layout (all instructions use same layout)
// ============================================================================

const ProgramAccounts = struct {
    authority: zero.Signer(0),
    target: zero.Mut(8), // 8 bytes for counter data
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "ZeroCU11111111111111111111111111111111111111"
    );

    /// Initialize counter to 0
    pub fn initialize(ctx: zero.Ctx(ProgramAccounts)) !void {
        if (!ctx.accounts.authority.isSigner()) {
            return error.MissingSigner;
        }

        const data = ctx.accounts.target.dataMut(8);
        const counter: *u64 = @ptrCast(@alignCast(data));
        counter.* = 0;
    }

    /// Increment counter
    pub fn increment(ctx: zero.Ctx(ProgramAccounts)) !void {
        if (!ctx.accounts.authority.isSigner()) {
            return error.MissingSigner;
        }

        const data = ctx.accounts.target.dataMut(8);
        const counter: *u64 = @ptrCast(@alignCast(data));
        counter.* += 1;
    }

    /// Get counter value (just validates, returns via log in real impl)
    pub fn get(ctx: zero.Ctx(ProgramAccounts)) !void {
        _ = ctx.accounts.target.data(8);
    }
};

// ============================================================================
// Multi-instruction export (7 CU each)
// ============================================================================

comptime {
    zero.multi(ProgramAccounts, .{
        zero.inst("initialize", Program.initialize),
        zero.inst("increment", Program.increment),
        zero.inst("get", Program.get),
    });
}
