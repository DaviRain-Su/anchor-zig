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
    const bump = context.data[0];

    // Use inline syscall to avoid stack issues
    const expected_key = try createPdaSyscall(
        &.{ "You pass butter", &.{bump} },
        context.program_id,
    );

    if (!allocated.id().equals(expected_key)) return error.InvalidPda;

    // Invoke system program to allocate using CPI helper
    try sol.system_program.allocateCpi(.{
        .account = allocated.info(),
        .space = SIZE,
        .seeds = &.{&.{ "You pass butter", &.{bump} }},
    });
}

// Inline syscall to avoid stack issues from SDK's createProgramAddress
inline fn createPdaSyscall(seeds: anytype, program_id: *align(1) const sol.public_key.PublicKey) !sol.public_key.PublicKey {
    const Syscall = struct {
        extern fn sol_create_program_address(
            seeds_ptr: [*]const []const u8,
            seeds_len: u64,
            program_id_ptr: *const sol.public_key.PublicKey,
            address_ptr: *sol.public_key.PublicKey,
        ) callconv(.c) u64;
    };

    var seeds_array: [seeds.len][]const u8 = undefined;
    inline for (seeds, 0..) |seed, i| seeds_array[i] = seed;

    var address: sol.public_key.PublicKey = undefined;
    const result = Syscall.sol_create_program_address(
        &seeds_array,
        seeds.len,
        program_id,
        &address,
    );
    
    if (result != 0) return error.InvalidSeeds;
    return address;
}
