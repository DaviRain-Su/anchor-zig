//! CPI Benchmark - zero_cu style entry()
//!
//! Same as rosetta but with discriminator check (like zero_cu entry()).
//! Uses manual discriminator check to match entry() behavior.

const std = @import("std");
const sol = @import("solana_program_sdk");
const sol_lib = @import("solana_program_library");

const system_ix = sol_lib.system;
const SIZE: u64 = 42;

// Precompute discriminator for "allocate"
const DISCRIMINATOR: u64 = blk: {
    @setEvalBranchQuota(10000);
    const preimage = "global:allocate";
    var hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(preimage, &hash, .{});
    break :blk @as(u64, @bitCast(hash[0..8].*));
};

export fn entrypoint(input: [*]u8) u64 {
    const context = sol.context.Context.load(input) catch return 1;
    
    // Check discriminator (like zero_cu entry())
    const disc: *align(1) const u64 = @ptrCast(context.data.ptr);
    if (disc.* != DISCRIMINATOR) return 1;
    
    const allocated = context.accounts[0];
    const bump = context.data[8]; // After 8-byte discriminator

    // Verify PDA
    const expected_key = sol.public_key.PublicKey.createProgramAddress(
        &.{ "You pass butter", &.{bump} },
        context.program_id.*,
    ) catch return 1;

    if (!allocated.id().equals(expected_key)) return 1;

    // Invoke system program to allocate
    system_ix.allocate(.{
        .account = allocated.info(),
        .space = SIZE,
        .seeds = &.{&.{ "You pass butter", &.{bump} }},
    }) catch return 1;

    return 0;
}
