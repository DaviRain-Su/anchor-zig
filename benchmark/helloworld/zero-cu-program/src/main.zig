//! HelloWorld using zero_cu program() API
//!
//! Uses program() + ixValidated() pattern like pubkey benchmark.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

const HelloAccounts = struct {};

pub fn hello(ctx: zero.Ctx(HelloAccounts)) !void {
    _ = ctx;
    sol.log.log("Hello world!");
}

comptime {
    zero.program(.{
        zero.ixValidated("hello", HelloAccounts, hello),
    });
}
