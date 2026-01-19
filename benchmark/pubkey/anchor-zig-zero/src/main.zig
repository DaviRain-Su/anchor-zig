//! Anchor-Zig Pubkey Comparison - Zero Overhead
//!
//! Same as raw zig but with discriminator check.

const anchor = @import("sol_anchor_zig");
const PublicKey = anchor.sdk.public_key.PublicKey;
const std = @import("std");

// Precomputed discriminator for "check" as u64
const CHECK_DISC: u64 = blk: {
    const disc = anchor.instructionDiscriminator("check");
    break :blk @bitCast(disc);
};

// Input buffer layout for 1 account with 1 byte data:
// [0..8]     num_accounts (u64) = 1
// [8..96]    Account.Data header (88 bytes)
//   [16..48]   id (32 bytes)
//   [48..80]   owner_id (32 bytes)  
// [96..97]   account data (1 byte)
// [97..10337] padding (10240 bytes)
// [10337->10344] align to 8
// [10344..10352] instruction data length
// [10352..] instruction data

export fn entrypoint(input: [*]u8) u64 {
    // Account id at offset 16
    const id: *align(1) PublicKey = @ptrCast(input + 16);
    // Owner id at offset 48
    const owner_id: *align(1) PublicKey = @ptrCast(input + 48);

    // Instruction data at offset 10352 (after align)
    const disc_ptr: *align(1) u64 = @ptrCast(input + 10352);
    
    // Check discriminator
    if (disc_ptr.* != CHECK_DISC) {
        return 1;
    }

    // Compare pubkeys
    if (id.equals(owner_id.*)) {
        return 0;
    } else {
        return 1;
    }
}
