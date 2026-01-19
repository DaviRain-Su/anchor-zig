//! Raw Zig HelloWorld - No framework overhead
//!
//! This is a minimal hello world program using raw Solana SDK.
//! Used as baseline to measure anchor-zig framework overhead.

const sol = @import("solana_program_sdk");

export fn entrypoint(_: [*]u8) u64 {
    sol.log.log("Hello world!");
    return 0;
}
