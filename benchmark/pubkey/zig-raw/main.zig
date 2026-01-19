const std = @import("std");
const PublicKey = @import("solana_program_sdk").public_key.PublicKey;

/// Check if account id equals owner id
/// Same logic as solana-program-rosetta/pubkey/zig
export fn entrypoint(input: [*]u8) u64 {
    const id: *align(1) PublicKey = @ptrCast(input + 16);
    const owner_id: *align(1) PublicKey = @ptrCast(input + 16 + 32);
    if (id.equals(owner_id.*)) {
        return 0;
    } else {
        return 1;
    }
}
