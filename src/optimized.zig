//! Optimized Program Entry
//!
//! Provides zero-overhead entry points (5-7 CU) while maintaining
//! Anchor-style abstractions.
//!
//! ## The Problem
//!
//! Standard Anchor uses runtime account parsing (~150 CU overhead).
//! ZeroCU achieves 5-7 CU but requires explicit data sizes.
//!
//! ## The Solution
//!
//! Use comptime offset calculation with Anchor-compatible handlers.
//! The key insight: we can compute offsets at comptime if we know
//! the account data sizes, then pass the zero-overhead context
//! to handlers that use Anchor's familiar API.
//!
//! ## Usage
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//!
//! // Step 1: Define account layout with sizes
//! const Layout = struct {
//!     authority: zero.Signer(0),
//!     counter: zero.Mut(CounterData),
//! };
//!
//! // Step 2: Define handler using ZeroCU context
//! pub fn increment(ctx: zero.Ctx(Layout)) !void {
//!     if (!ctx.accounts.authority.isSigner()) {
//!         return error.MissingSigner;
//!     }
//!     ctx.accounts.counter.getMut().count += 1;
//! }
//!
//! // Step 3: Export with zero overhead
//! comptime {
//!     // Single instruction (5 CU)
//!     zero.entry(Layout, "increment", increment);
//!
//!     // Or multi-instruction (7 CU each)
//!     zero.multi(Layout, .{
//!         zero.inst("init", init),
//!         zero.inst("increment", increment),
//!     });
//! }
//! ```
//!
//! ## Why This Works
//!
//! 1. `zero.Signer(0)`, `zero.Mut(T)` encode data sizes at comptime
//! 2. `zero.Ctx(Layout)` generates accessors with precomputed offsets
//! 3. The entrypoint does a single u64 discriminator compare
//! 4. No runtime account parsing loop = 5-7 CU total
//!
//! ## Comparison
//!
//! | Approach        | CU    | Abstraction Level |
//! |-----------------|-------|-------------------|
//! | Raw Zig         | 5     | None              |
//! | zero_cu         | 5-7   | High (typed)      |
//! | Standard Anchor | ~150  | High (validated)  |

const std = @import("std");
const sol = @import("solana_program_sdk");
const zero_cu = @import("zero_cu.zig");
const discriminator_mod = @import("discriminator.zig");

// Re-export zero_cu types for convenience
pub const Signer = zero_cu.Signer;
pub const Mut = zero_cu.Mut;
pub const Readonly = zero_cu.Readonly;
pub const Ctx = zero_cu.Ctx;
pub const entry = zero_cu.entry;
pub const multi = zero_cu.multi;
pub const inst = zero_cu.inst;

// Keep ValidationLevel for legacy compatibility
pub const ValidationLevel = enum {
    full,
    minimal,
    unchecked,
};

/// Legacy export function (uses SDK Context.load, ~31+ CU)
/// Prefer zero_cu.entry() or zero_cu.multi() for 5-7 CU
pub fn exportEntrypoint(comptime Program: type, comptime level: ValidationLevel) void {
    _ = level;
    const context_mod = @import("context.zig");

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            @setRuntimeSafety(false);

            const ctx = sol.context.Context.load(input) catch return 1;
            const data = ctx.data;

            if (data.len < 8) return 1;

            const disc_u64: u64 = @bitCast(data[0..8].*);

            inline for (@typeInfo(Program.instructions).@"struct".decls) |decl| {
                const InstructionType = @field(Program.instructions, decl.name);
                if (@TypeOf(InstructionType) == type and @hasDecl(InstructionType, "Accounts")) {
                    const expected_u64: u64 = comptime @bitCast(
                        discriminator_mod.instructionDiscriminator(decl.name),
                    );

                    if (disc_u64 == expected_u64) {
                        const handler = @field(Program, decl.name);
                        const Accounts = InstructionType.Accounts;

                        var infos: [64]sol.account.Account.Info = undefined;
                        for (0..ctx.num_accounts) |i| {
                            infos[i] = ctx.accounts[i].info();
                        }

                        const anchor_ctx = context_mod.parseContext(
                            Accounts,
                            ctx.program_id,
                            infos[0..ctx.num_accounts],
                        ) catch return 1;

                        if (handler(anchor_ctx)) |_| return 0 else |_| return 1;
                    }
                }
            }

            return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}
