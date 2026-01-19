//! ZeroCU Program API - Single Instruction
//!
//! Same as zero-cu-single but using program() API instead of entry()

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

const CheckAccounts = struct {
    target: zero.Readonly(1),
};

pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
    const target = ctx.accounts.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

comptime {
    zero.program(.{
        zero.ixValidated("check", CheckAccounts, check),
    });
}
