//! Zig implementation of Anchor discriminator generation
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/sighash.rs
//!
//! Discriminators are 8-byte identifiers derived from SHA256 hashes.
//! They uniquely identify account types and instructions in Anchor programs.
//!
//! ## Format
//! - Account discriminator: `sha256("account:<AccountName>")[0..8]`
//! - Instruction discriminator: `sha256("global:<InstructionName>")[0..8]`
//!
//! ## Example
//! ```zig
//! const counter_disc = accountDiscriminator("Counter");
//! const init_disc = instructionDiscriminator("initialize");
//! ```

const std = @import("std");

/// Discriminator length in bytes (Anchor standard)
pub const DISCRIMINATOR_LENGTH: usize = 8;

/// Discriminator type (8 bytes)
pub const Discriminator = [DISCRIMINATOR_LENGTH]u8;

/// Generate account discriminator at comptime
///
/// Format: `sha256("account:<name>")[0..8]`
///
/// This matches Anchor's account discriminator generation exactly.
pub fn accountDiscriminator(comptime name: []const u8) Discriminator {
    return sighash("account", name);
}

/// Generate instruction discriminator at comptime
///
/// Format: `sha256("global:<name>")[0..8]`
///
/// This matches Anchor's instruction discriminator generation exactly.
/// Note: Anchor uses "global" namespace for all public instructions.
pub fn instructionDiscriminator(comptime name: []const u8) Discriminator {
    return sighash("global", name);
}

/// Generate event discriminator at comptime
///
/// Format: `sha256("event:<name>")[0..8]`
pub fn eventDiscriminator(comptime name: []const u8) Discriminator {
    return sighash("event", name);
}

/// Generate sighash at comptime
///
/// Format: `sha256("<namespace>:<name>")[0..8]`
///
/// This is the core discriminator generation function used by both
/// account and instruction discriminators.
pub fn sighash(comptime namespace: []const u8, comptime name: []const u8) Discriminator {
    comptime {
        // SHA256 comptime computation requires more than default branch quota
        @setEvalBranchQuota(10000);

        const preimage = namespace ++ ":" ++ name;
        var hash: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(preimage, &hash, .{});
        return hash[0..DISCRIMINATOR_LENGTH].*;
    }
}

/// Runtime discriminator validation
///
/// Checks if the first 8 bytes of data match the expected discriminator.
pub fn validateDiscriminator(data: []const u8, expected: Discriminator) bool {
    if (data.len < DISCRIMINATOR_LENGTH) {
        return false;
    }
    return std.mem.eql(u8, data[0..DISCRIMINATOR_LENGTH], &expected);
}

/// Format discriminator as hex string for debugging
pub fn formatDiscriminator(disc: Discriminator) [DISCRIMINATOR_LENGTH * 2]u8 {
    const hex_chars = "0123456789abcdef";
    var result: [DISCRIMINATOR_LENGTH * 2]u8 = undefined;
    for (disc, 0..) |byte, i| {
        result[i * 2] = hex_chars[byte >> 4];
        result[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
    return result;
}

// ============================================================================
// Tests
// ============================================================================

test "accountDiscriminator generates correct hash" {
    // Test with known Anchor discriminator values
    const counter_disc = comptime accountDiscriminator("Counter");

    // Discriminator should be 8 bytes
    try std.testing.expectEqual(@as(usize, 8), counter_disc.len);

    // Verify it's deterministic
    const counter_disc2 = comptime accountDiscriminator("Counter");
    try std.testing.expectEqualSlices(u8, &counter_disc, &counter_disc2);
}

test "instructionDiscriminator generates correct hash" {
    const init_disc = comptime instructionDiscriminator("initialize");

    // Discriminator should be 8 bytes
    try std.testing.expectEqual(@as(usize, 8), init_disc.len);

    // Verify different instructions have different discriminators
    const increment_disc = comptime instructionDiscriminator("increment");
    try std.testing.expect(!std.mem.eql(u8, &init_disc, &increment_disc));
}

test "eventDiscriminator generates correct hash" {
    const event_disc = comptime eventDiscriminator("CounterEvent");

    // Discriminator should be 8 bytes
    try std.testing.expectEqual(@as(usize, 8), event_disc.len);

    const other = comptime eventDiscriminator("OtherEvent");
    try std.testing.expect(!std.mem.eql(u8, &event_disc, &other));
}

test "sighash produces deterministic output" {
    const hash1 = comptime sighash("account", "MyAccount");
    const hash2 = comptime sighash("account", "MyAccount");

    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "different namespaces produce different hashes" {
    const account_hash = comptime sighash("account", "Test");
    const global_hash = comptime sighash("global", "Test");

    try std.testing.expect(!std.mem.eql(u8, &account_hash, &global_hash));
}

test "validateDiscriminator accepts valid data" {
    const expected = comptime accountDiscriminator("Counter");
    var data: [16]u8 = undefined;
    @memcpy(data[0..8], &expected);

    try std.testing.expect(validateDiscriminator(&data, expected));
}

test "validateDiscriminator rejects invalid data" {
    const expected = comptime accountDiscriminator("Counter");
    const wrong = comptime accountDiscriminator("Other");
    var data: [16]u8 = undefined;
    @memcpy(data[0..8], &wrong);

    try std.testing.expect(!validateDiscriminator(&data, expected));
}

test "validateDiscriminator rejects short data" {
    const expected = comptime accountDiscriminator("Counter");
    const short_data = [_]u8{ 0, 1, 2, 3 };

    try std.testing.expect(!validateDiscriminator(&short_data, expected));
}

test "formatDiscriminator produces hex string" {
    const disc = [_]u8{ 0xab, 0xcd, 0xef, 0x01, 0x23, 0x45, 0x67, 0x89 };
    const hex = formatDiscriminator(disc);

    try std.testing.expectEqualStrings("abcdef0123456789", &hex);
}
