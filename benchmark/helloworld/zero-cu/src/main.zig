//! HelloWorld using zero_cu API
//!
//! Minimal hello world program to measure framework overhead.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// ============================================================================
// Accounts (empty for hello world)
// ============================================================================

const HelloAccounts = struct {
    // No accounts needed for hello world
};

// ============================================================================
// Handler
// ============================================================================

pub fn hello(ctx: zero.Ctx(HelloAccounts)) !void {
    _ = ctx;
    sol.log.log("Hello world!");
}

// ============================================================================
// Program Entry
// ============================================================================

comptime {
    zero.entry(HelloAccounts, "hello", hello);
}
