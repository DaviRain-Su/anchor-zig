//! HelloWorld using zero_cu - No discriminator check
//!
//! Uses entryRaw() to skip discriminator check, matching rosetta exactly.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

const HelloAccounts = struct {};

pub fn hello(ctx: zero.Ctx(HelloAccounts)) !void {
    _ = ctx;
    sol.log.log("Hello world!");
}

// Use raw entry without discriminator check
comptime {
    zero.entryRaw(HelloAccounts, hello);
}
