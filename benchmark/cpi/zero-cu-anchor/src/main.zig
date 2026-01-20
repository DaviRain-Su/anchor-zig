//! CPI Benchmark - Using anchor-zig zero_cu program() API
//!
//! Demonstrates CPI (Cross-Program Invocation) with anchor-zig.
//! Uses zero.program() with dynamic context loading.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

const SIZE: u64 = 42;

// ============================================================================
// Accounts
// ============================================================================

const AllocateAccounts = struct {
    allocated: zero.Mut(0),
    system_program: zero.Readonly(0),
};

// ============================================================================
// Arguments
// ============================================================================

const AllocateArgs = struct {
    bump: u8,
};

// ============================================================================
// Handler
// ============================================================================

fn allocateHandler(ctx: zero.Ctx(AllocateAccounts)) !void {
    const args = ctx.args(AllocateArgs);
    const allocated = ctx.accounts().allocated;

    // Verify PDA using syscall
    const expected_key = sol.public_key.createProgramAddress(
        &.{ "You pass butter", &.{args.bump} },
        ctx.programId().*,
    ) catch return error.InvalidPda;

    if (!allocated.id().*.equals(expected_key)) {
        return error.InvalidPda;
    }

    // Invoke system program to allocate using CPI helper
    sol.system_program.allocateCpi(.{
        .account = allocated.info(),
        .space = SIZE,
        .seeds = &.{&.{ "You pass butter", &.{args.bump} }},
    }) catch return error.AllocateFailed;
}

// ============================================================================
// Program Entry
// ============================================================================

comptime {
    zero.program(.{
        zero.ix("allocate", AllocateAccounts, allocateHandler),
    });
}
