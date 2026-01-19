//! CPI Benchmark - Raw Zig (same as rosetta)
//!
//! Verifies PDA and invokes system program to allocate 42 bytes.
//! Uses DaviRain-Su/solana-program-sdk-zig

const sol = @import("solana_program_sdk");

const SIZE: u64 = 42;

export fn entrypoint(input: [*]u8) u64 {
    process(input) catch return 1;
    return 0;
}

fn process(input: [*]u8) !void {
    const context = sol.context.Context.load(input) catch return error.ContextLoadFailed;
    const allocated = context.accounts[0];

    // Now uses the fixed SDK createProgramAddress (no stack overflow)
    const expected_key = sol.public_key.createProgramAddress(
        &.{ "You pass butter", &.{context.data[0]} },
        context.program_id.*,
    ) catch return error.PdaFailed;

    if (!allocated.id().equals(expected_key)) return error.InvalidPda;

    // Invoke system program to allocate using CPI helper
    try sol.system_program.allocateCpi(.{
        .account = allocated.info(),
        .space = SIZE,
        .seeds = &.{&.{ "You pass butter", &.{context.data[0]} }},
    });
}
