//! Anchor-Zig Pubkey Comparison - Zero CU with Abstraction
//!
//! Uses ZeroContext abstraction for readable code with zero overhead.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// Define accounts with their data sizes
const CheckAccounts = struct {
    target: zero.ZeroReadonly(1), // 1 byte account data
};

// Create zero-overhead context type
const Ctx = zero.ZeroContext(.{
    .accounts = zero.accountDataLengths(CheckAccounts),
});

// Precomputed discriminator
const CHECK_DISC = anchor.instructionDiscriminator("check");

fn check(ctx: Ctx) u64 {
    const target = ctx.account(0);

    // Compare id with owner_id
    if (target.id().equals(target.ownerId().*)) {
        return 0;
    } else {
        return 1;
    }
}

export fn entrypoint(input: [*]u8) u64 {
    const ctx = Ctx.load(input);

    // Check discriminator
    if (!ctx.checkDiscriminator(CHECK_DISC)) {
        return 1;
    }

    return check(ctx);
}
