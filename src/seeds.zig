//! Zig implementation of Anchor seed types for PDA derivation
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/seeds.rs
//!
//! Seeds define the inputs to PDA (Program Derived Address) derivation.
//! In Anchor, seeds are specified via `#[account(seeds = [...], bump)]`.
//! In sol-anchor-zig, they are defined as compile-time seed specifications.
//!
//! ## Seed Types
//! - `literal`: Static byte strings (e.g., "counter", "vault")
//! - `account`: Reference to another account's public key
//! - `field`: Reference to a field in the account's data
//!
//! ## Example
//! ```zig
//! const Counter = anchor.Account(CounterData, .{
//!     .discriminator = anchor.accountDiscriminator("Counter"),
//!     .seeds = &.{
//!         anchor.seed("counter"),
//!         anchor.seedAccount("authority"),
//!     },
//!     .bump = true,
//! });
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.PublicKey;

/// Maximum number of seeds for PDA derivation
pub const MAX_SEEDS: usize = 16;

/// Maximum length of a single seed
pub const MAX_SEED_LEN: usize = 32;

/// Seed specification for PDA derivation
///
/// Specifies how to obtain a seed value at runtime. Can be a literal
/// byte string, a reference to another account's key, or a reference
/// to a field in the account data.
pub const SeedSpec = union(enum) {
    /// Literal byte string seed
    ///
    /// Example: `anchor.seed("counter")` produces `{ .literal = "counter" }`
    literal: []const u8,

    /// Reference to another account's public key
    ///
    /// The account name must match a field in the Accounts struct.
    /// Example: `anchor.seedAccount("authority")` produces `{ .account = "authority" }`
    account: []const u8,

    /// Reference to a field in the account's data
    ///
    /// The field must be a PublicKey or [N]u8 type.
    /// Example: `anchor.seedField("user")` produces `{ .field = "user" }`
    field: []const u8,

    /// Reference to a bump seed from context
    ///
    /// Used when the bump needs to be included in seeds for verification.
    bump: []const u8,
};

/// Create a literal seed specification
///
/// Example:
/// ```zig
/// const seeds = &.{ seed("counter"), seed("v1") };
/// ```
pub fn seed(comptime literal: []const u8) SeedSpec {
    return .{ .literal = literal };
}

/// Create an account reference seed specification
///
/// The account name must match a field in the instruction's Accounts struct.
/// At runtime, the account's public key bytes will be used as the seed.
///
/// Example:
/// ```zig
/// const seeds = &.{ seed("user_data"), seedAccount("user") };
/// ```
pub fn seedAccount(comptime account_name: []const u8) SeedSpec {
    return .{ .account = account_name };
}

/// Create a field reference seed specification
///
/// The field name refers to a PublicKey or byte array field in the account data.
/// At runtime, the field's bytes will be used as the seed.
///
/// Example:
/// ```zig
/// const seeds = &.{ seed("owned_by"), seedField("owner") };
/// ```
pub fn seedField(comptime field_name: []const u8) SeedSpec {
    return .{ .field = field_name };
}

/// Create a bump reference seed specification
///
/// References a bump seed that will be resolved from context.
///
/// Example:
/// ```zig
/// const seeds = &.{ seed("counter"), seedBump("counter") };
/// ```
pub fn seedBump(comptime bump_name: []const u8) SeedSpec {
    return .{ .bump = bump_name };
}

/// Buffer for resolved seeds at runtime
pub const SeedBuffer = struct {
    /// Storage for seed byte slices
    seeds: [MAX_SEEDS][]const u8 = undefined,
    /// Backing storage for small seeds (like bumps)
    backing: [MAX_SEEDS][MAX_SEED_LEN]u8 = undefined,
    /// Number of seeds
    len: usize = 0,

    /// Get the resolved seeds as a slice
    pub fn asSlice(self: *const SeedBuffer) []const []const u8 {
        return self.seeds[0..self.len];
    }

    /// Convert to tuple for use with createProgramAddress
    pub fn asTuple(self: *const SeedBuffer) SeedTuple {
        return .{ .buffer = self };
    }
};

/// Wrapper to allow SeedBuffer to be used with createProgramAddress
pub const SeedTuple = struct {
    buffer: *const SeedBuffer,

    pub const len = MAX_SEEDS;

    pub fn get(self: SeedTuple, comptime index: usize) []const u8 {
        return self.buffer.seeds[index];
    }
};

/// Seed resolution errors
pub const SeedError = error{
    /// Seed value exceeds maximum length
    SeedTooLong,
    /// Too many seeds specified
    TooManySeeds,
    /// Account field not found during resolution
    AccountNotFound,
    /// Field not found in account data
    FieldNotFound,
    /// Bump not found in context
    BumpNotFound,
    /// Invalid seed type for resolution
    InvalidSeedType,
};

/// Resolve seeds at compile time (for literal-only seeds)
///
/// Returns a tuple of seed byte slices suitable for `createProgramAddress`.
/// Only works with literal seeds - account/field references require runtime resolution.
pub fn resolveComptimeSeeds(comptime specs: []const SeedSpec) [specs.len][]const u8 {
    comptime {
        var result: [specs.len][]const u8 = undefined;
        for (specs, 0..) |spec, i| {
            switch (spec) {
                .literal => |lit| {
                    if (lit.len > MAX_SEED_LEN) {
                        @compileError("Seed exceeds maximum length of 32 bytes");
                    }
                    result[i] = lit;
                },
                .account, .field, .bump => {
                    @compileError("Cannot resolve account/field/bump references at compile time");
                },
            }
        }
        return result;
    }
}

/// Check if all seeds are literals (resolvable at compile time)
pub fn areAllLiteralSeeds(comptime specs: []const SeedSpec) bool {
    comptime {
        for (specs) |spec| {
            switch (spec) {
                .literal => {},
                .account, .field, .bump => return false,
            }
        }
        return true;
    }
}

/// Get the number of seeds
pub fn seedCount(comptime specs: []const SeedSpec) usize {
    return specs.len;
}

/// Validate seed specifications at compile time
pub fn validateSeeds(comptime specs: []const SeedSpec) void {
    comptime {
        if (specs.len > MAX_SEEDS) {
            @compileError("Too many seeds: maximum is 16");
        }

        for (specs) |spec| {
            switch (spec) {
                .literal => |lit| {
                    if (lit.len > MAX_SEED_LEN) {
                        @compileError("Seed exceeds maximum length of 32 bytes");
                    }
                },
                .account => |name| {
                    if (name.len == 0) {
                        @compileError("Account seed name cannot be empty");
                    }
                },
                .field => |name| {
                    if (name.len == 0) {
                        @compileError("Field seed name cannot be empty");
                    }
                },
                .bump => |name| {
                    if (name.len == 0) {
                        @compileError("Bump seed name cannot be empty");
                    }
                },
            }
        }
    }
}

/// Compile-time hash for field name lookup
pub fn fieldNameHash(comptime name: []const u8) u64 {
    comptime {
        var hash: u64 = 5381;
        for (name) |c| {
            hash = ((hash << 5) +% hash) +% c;
        }
        return hash;
    }
}

/// Append a seed to a SeedBuffer
pub fn appendSeed(buffer: *SeedBuffer, seed_data: []const u8) SeedError!void {
    if (buffer.len >= MAX_SEEDS) {
        return SeedError.TooManySeeds;
    }
    if (seed_data.len > MAX_SEED_LEN) {
        return SeedError.SeedTooLong;
    }
    buffer.seeds[buffer.len] = seed_data;
    buffer.len += 1;
}

/// Append a bump seed (single byte) to a SeedBuffer
pub fn appendBumpSeed(buffer: *SeedBuffer, bump: u8) SeedError!void {
    if (buffer.len >= MAX_SEEDS) {
        return SeedError.TooManySeeds;
    }
    buffer.backing[buffer.len][0] = bump;
    buffer.seeds[buffer.len] = buffer.backing[buffer.len][0..1];
    buffer.len += 1;
}

/// Check if seed specs contain any account references
pub fn hasAccountRefs(comptime specs: []const SeedSpec) bool {
    comptime {
        for (specs) |spec| {
            switch (spec) {
                .account => return true,
                else => {},
            }
        }
        return false;
    }
}

/// Check if seed specs contain any field references
pub fn hasFieldRefs(comptime specs: []const SeedSpec) bool {
    comptime {
        for (specs) |spec| {
            switch (spec) {
                .field => return true,
                else => {},
            }
        }
        return false;
    }
}

/// Check if seed specs contain any bump references
pub fn hasBumpRefs(comptime specs: []const SeedSpec) bool {
    comptime {
        for (specs) |spec| {
            switch (spec) {
                .bump => return true,
                else => {},
            }
        }
        return false;
    }
}

/// Get all account reference names from seed specs
pub fn getAccountRefNames(comptime specs: []const SeedSpec) []const []const u8 {
    comptime {
        var count: usize = 0;
        for (specs) |spec| {
            switch (spec) {
                .account => count += 1,
                else => {},
            }
        }

        if (count == 0) return &[_][]const u8{};

        var names: [count][]const u8 = undefined;
        var idx: usize = 0;
        for (specs) |spec| {
            switch (spec) {
                .account => |name| {
                    names[idx] = name;
                    idx += 1;
                },
                else => {},
            }
        }
        return &names;
    }
}

/// Get all field reference names from seed specs
pub fn getFieldRefNames(comptime specs: []const SeedSpec) []const []const u8 {
    comptime {
        var count: usize = 0;
        for (specs) |spec| {
            switch (spec) {
                .field => count += 1,
                else => {},
            }
        }

        if (count == 0) return &[_][]const u8{};

        var names: [count][]const u8 = undefined;
        var idx: usize = 0;
        for (specs) |spec| {
            switch (spec) {
                .field => |name| {
                    names[idx] = name;
                    idx += 1;
                },
                else => {},
            }
        }
        return &names;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "seed creates literal seed spec" {
    const s = seed("counter");
    try std.testing.expectEqual(SeedSpec{ .literal = "counter" }, s);
}

test "seedAccount creates account seed spec" {
    const s = seedAccount("authority");
    try std.testing.expectEqual(SeedSpec{ .account = "authority" }, s);
}

test "seedField creates field seed spec" {
    const s = seedField("owner");
    try std.testing.expectEqual(SeedSpec{ .field = "owner" }, s);
}

test "seedBump creates bump seed spec" {
    const s = seedBump("counter");
    try std.testing.expectEqual(SeedSpec{ .bump = "counter" }, s);
}

test "resolveComptimeSeeds works for literals" {
    comptime {
        const specs = &[_]SeedSpec{
            seed("hello"),
            seed("world"),
        };
        const resolved = resolveComptimeSeeds(specs);
        std.debug.assert(std.mem.eql(u8, "hello", resolved[0]));
        std.debug.assert(std.mem.eql(u8, "world", resolved[1]));
    }
}

test "areAllLiteralSeeds returns true for literals only" {
    comptime {
        const literal_specs = &[_]SeedSpec{
            seed("a"),
            seed("b"),
        };
        std.debug.assert(areAllLiteralSeeds(literal_specs));

        const mixed_specs = &[_]SeedSpec{
            seed("a"),
            seedAccount("user"),
        };
        std.debug.assert(!areAllLiteralSeeds(mixed_specs));
    }
}

test "seedCount returns correct count" {
    comptime {
        const specs = &[_]SeedSpec{
            seed("a"),
            seed("b"),
            seed("c"),
        };
        std.debug.assert(seedCount(specs) == 3);
    }
}

test "validateSeeds passes for valid specs" {
    comptime {
        const specs = &[_]SeedSpec{
            seed("counter"),
            seedAccount("authority"),
            seedField("user"),
        };
        // Should not compile error
        validateSeeds(specs);
    }
}

test "fieldNameHash produces consistent hashes" {
    comptime {
        const hash1 = fieldNameHash("authority");
        const hash2 = fieldNameHash("authority");
        const hash3 = fieldNameHash("different");

        std.debug.assert(hash1 == hash2);
        std.debug.assert(hash1 != hash3);
    }
}

test "SeedBuffer basic usage" {
    var buffer = SeedBuffer{};

    buffer.seeds[0] = "hello";
    buffer.seeds[1] = "world";
    buffer.len = 2;

    const slice = buffer.asSlice();
    try std.testing.expectEqual(@as(usize, 2), slice.len);
    try std.testing.expectEqualStrings("hello", slice[0]);
    try std.testing.expectEqualStrings("world", slice[1]);
}

test "MAX_SEEDS is 16" {
    try std.testing.expectEqual(@as(usize, 16), MAX_SEEDS);
}

test "MAX_SEED_LEN is 32" {
    try std.testing.expectEqual(@as(usize, 32), MAX_SEED_LEN);
}

test "appendSeed adds seed to buffer" {
    var buffer = SeedBuffer{};

    try appendSeed(&buffer, "hello");
    try appendSeed(&buffer, "world");

    try std.testing.expectEqual(@as(usize, 2), buffer.len);
    try std.testing.expectEqualStrings("hello", buffer.seeds[0]);
    try std.testing.expectEqualStrings("world", buffer.seeds[1]);
}

test "appendBumpSeed adds single byte seed" {
    var buffer = SeedBuffer{};

    try appendBumpSeed(&buffer, 255);

    try std.testing.expectEqual(@as(usize, 1), buffer.len);
    try std.testing.expectEqual(@as(usize, 1), buffer.seeds[0].len);
    try std.testing.expectEqual(@as(u8, 255), buffer.seeds[0][0]);
}

test "hasAccountRefs detects account references" {
    comptime {
        const with_account = &[_]SeedSpec{
            seed("prefix"),
            seedAccount("authority"),
        };
        std.debug.assert(hasAccountRefs(with_account));

        const without_account = &[_]SeedSpec{
            seed("prefix"),
            seedField("owner"),
        };
        std.debug.assert(!hasAccountRefs(without_account));
    }
}

test "hasFieldRefs detects field references" {
    comptime {
        const with_field = &[_]SeedSpec{
            seed("prefix"),
            seedField("owner"),
        };
        std.debug.assert(hasFieldRefs(with_field));

        const without_field = &[_]SeedSpec{
            seed("prefix"),
            seedAccount("authority"),
        };
        std.debug.assert(!hasFieldRefs(without_field));
    }
}

test "getAccountRefNames returns account names" {
    comptime {
        const specs = &[_]SeedSpec{
            seed("prefix"),
            seedAccount("authority"),
            seedAccount("user"),
            seedField("owner"),
        };
        const names = getAccountRefNames(specs);
        std.debug.assert(names.len == 2);
        std.debug.assert(std.mem.eql(u8, "authority", names[0]));
        std.debug.assert(std.mem.eql(u8, "user", names[1]));
    }
}

test "getFieldRefNames returns field names" {
    comptime {
        const specs = &[_]SeedSpec{
            seed("prefix"),
            seedField("owner"),
            seedAccount("authority"),
            seedField("mint"),
        };
        const names = getFieldRefNames(specs);
        std.debug.assert(names.len == 2);
        std.debug.assert(std.mem.eql(u8, "owner", names[0]));
        std.debug.assert(std.mem.eql(u8, "mint", names[1]));
    }
}
