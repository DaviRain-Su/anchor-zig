//! Anchor-Zig Pubkey Comparison - Unified Zero-CU API
//!
//! Uses Anchor-style API with zero runtime overhead.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Definitions - Anchor style
// ============================================================================

const CheckAccounts = struct {
    target: zero.ZeroReadonly(1),
};

// ============================================================================
// Program Definition
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "PubkeyComp111111111111111111111111111111111"
    );

    pub const instructions = struct {
        pub const check = struct {
            pub const Accounts = CheckAccounts;
        };
    };

    pub fn check(ctx: zero.ZeroInstructionContext(CheckAccounts)) !void {
        const target = ctx.accounts.target;
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Entrypoint with Zero-CU dispatch
// ============================================================================

const CHECK_DISC: u64 = @bitCast(anchor.instructionDiscriminator("check"));
const Ctx = zero.ZeroInstructionContext(CheckAccounts);

export fn entrypoint(input: [*]u8) u64 {
    // Check discriminator at comptime-known offset
    const disc: *align(1) const u64 = @ptrCast(input + Ctx.ix_data_offset);
    if (disc.* != CHECK_DISC) {
        return 1;
    }

    // Dispatch to handler
    const ctx = Ctx.load(input);
    if (Program.check(ctx)) |_| {
        return 0;
    } else |_| {
        return 1;
    }
}
