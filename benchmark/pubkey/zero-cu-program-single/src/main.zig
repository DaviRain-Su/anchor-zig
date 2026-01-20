//! ZeroCU Program API - Single Instruction with Validation
//!
//! Same as zero-cu-single but using program() API with owner constraint

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// Program ID for owner constraint
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

const CheckAccounts = struct {
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID, // Auto-validated by ixValidated
    }),
};

pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
    const target = ctx.accounts().target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

comptime {
    zero.program(.{
        zero.ixValidated("check", CheckAccounts, check),
    });
}
