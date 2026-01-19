//! Anchor-Zig Pubkey Comparison - Ultra Optimized
//!
//! Direct entrypoint with discriminator - minimal overhead.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// Precomputed discriminator for "check"
const CHECK_DISC: u64 = blk: {
    const disc = anchor.instructionDiscriminator("check");
    break :blk @bitCast(disc);
};

export fn entrypoint(input: [*]u8) u64 {
    // Parse num_accounts
    const num_accounts: *u64 = @ptrCast(@alignCast(input));
    if (num_accounts.* < 1) return 1;

    // Skip to first account data (after num_accounts u64)
    var ptr: [*]u8 = input + 8;

    // Read account header
    const account_data: *sol.Account.Data = @ptrCast(@alignCast(ptr));

    // Skip past account to instruction data
    const account_size = sol.Account.DATA_HEADER + account_data.data_len + 10 * 1024 + 8;
    ptr += account_size;
    ptr = @ptrFromInt(std.mem.alignForward(u64, @intFromPtr(ptr), 8));

    // Read instruction data length
    const data_len: *u64 = @ptrCast(@alignCast(ptr));
    ptr += 8;

    // Check discriminator
    if (data_len.* < 8) return 1;
    const disc: u64 = @bitCast(ptr[0..8].*);
    if (disc != CHECK_DISC) return 1;

    // Compare pubkeys
    if (account_data.id.equals(account_data.owner_id)) {
        return 0;
    } else {
        return 1;
    }
}

const std = @import("std");
