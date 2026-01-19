//! CPI Benchmark - Raw Zig (same as rosetta)
//!
//! Verifies PDA and invokes system program to allocate 42 bytes.

const sol = @import("solana_program_sdk");
const sol_lib = @import("solana_program_library");

const system_ix = sol_lib.system;
const SIZE: u64 = 42;

export fn entrypoint(input: [*]u8) u64 {
    const context = sol.context.Context.load(input) catch return 1;
    const allocated = context.accounts[0];

    const expected_key = sol.public_key.PublicKey.createProgramAddress(
        &.{ "You pass butter", &.{context.data[0]} },
        context.program_id.*,
    ) catch return 1;

    if (!allocated.id().equals(expected_key)) return 1;

    // Invoke system program to allocate
    system_ix.allocate(.{
        .account = allocated.info(),
        .space = SIZE,
        .seeds = &.{&.{ "You pass butter", &.{context.data[0]} }},
    }) catch return 1;

    return 0;
}
