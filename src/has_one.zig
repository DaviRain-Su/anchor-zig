//! Zig implementation of Anchor has_one constraint
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/constraints.rs
//!
//! Validates that a field in account data matches another account's public key.
//! This is commonly used to ensure that an authority field in an account matches
//! the signer account provided in the instruction.
//!
//! ## Example
//! ```zig
//! const Vault = anchor.Account(VaultData, .{
//!     .discriminator = anchor.accountDiscriminator("Vault"),
//!     .has_one = &.{
//!         .{ .field = "authority", .target = "authority" },
//!     },
//! });
//!
//! const WithdrawAccounts = struct {
//!     vault: Vault,
//!     authority: anchor.Signer,  // Must match vault.data.authority
//! };
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.PublicKey;

/// Has-one constraint specification
///
/// Defines a relationship between a field in account data and another
/// account in the accounts struct.
pub const HasOneSpec = struct {
    /// Field name in account data (must be PublicKey or [32]u8 type)
    field: []const u8,

    /// Account name in Accounts struct to compare against
    ///
    /// The target account must have a `key()` method that returns
    /// a pointer to its PublicKey.
    target: []const u8,
};

/// Has-one validation errors
pub const HasOneError = error{
    /// Field value does not match target account's public key
    ConstraintHasOne,
};

/// Validate a single has_one constraint
///
/// Checks that account_data.field == target_key.
/// Supports both PublicKey fields and [32]u8 byte array fields.
///
/// Example:
/// ```zig
/// try validateHasOne(
///     VaultData,
///     vault_account.data,
///     "authority",
///     ctx.accounts.authority.key(),
/// );
/// ```
pub fn validateHasOne(
    comptime T: type,
    account_data: *const T,
    comptime field_name: []const u8,
    target_key: *const PublicKey,
) HasOneError!void {
    const field_value = @field(account_data.*, field_name);
    const FieldType = @TypeOf(field_value);

    // Get field bytes based on type
    const field_bytes: []const u8 = if (FieldType == PublicKey)
        &field_value.bytes
    else if (FieldType == [32]u8)
        &field_value
    else if (@typeInfo(FieldType) == .pointer) blk: {
        const child = @typeInfo(FieldType).pointer.child;
        if (child == PublicKey) {
            break :blk &field_value.bytes;
        } else {
            @compileError("has_one field must be PublicKey, [32]u8, or *const PublicKey, got: " ++ @typeName(FieldType));
        }
    } else {
        @compileError("has_one field must be PublicKey, [32]u8, or *const PublicKey, got: " ++ @typeName(FieldType));
    };

    if (!std.mem.eql(u8, field_bytes, &target_key.bytes)) {
        return HasOneError.ConstraintHasOne;
    }
}

/// Validate a has_one constraint by comparing raw bytes
///
/// Lower-level API for when you have raw byte slices.
pub fn validateHasOneBytes(
    field_bytes: []const u8,
    target_bytes: []const u8,
) HasOneError!void {
    if (field_bytes.len != 32 or target_bytes.len != 32) {
        return HasOneError.ConstraintHasOne;
    }
    if (!std.mem.eql(u8, field_bytes, target_bytes)) {
        return HasOneError.ConstraintHasOne;
    }
}

/// Check if has_one constraint is satisfied (returns bool instead of error)
pub fn checkHasOne(
    comptime T: type,
    account_data: *const T,
    comptime field_name: []const u8,
    target_key: *const PublicKey,
) bool {
    validateHasOne(T, account_data, field_name, target_key) catch return false;
    return true;
}

/// Get the field value for has_one validation (comptime helper)
///
/// Returns a pointer to the field's bytes for comparison.
pub fn getHasOneFieldBytes(
    comptime T: type,
    account_data: *const T,
    comptime field_name: []const u8,
) *const [32]u8 {
    const field_ptr = &@field(account_data.*, field_name);
    const FieldType = @TypeOf(field_ptr.*);

    if (FieldType == PublicKey) {
        return &field_ptr.bytes;
    } else if (FieldType == [32]u8) {
        return field_ptr;
    } else {
        @compileError("has_one field must be PublicKey or [32]u8");
    }
}

// ============================================================================
// Tests
// ============================================================================

test "validateHasOne succeeds when field matches target" {
    const TestData = struct {
        authority: PublicKey,
        value: u64,
    };

    const key = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const data = TestData{
        .authority = key,
        .value = 100,
    };

    try validateHasOne(TestData, &data, "authority", &key);
}

test "validateHasOne fails when field does not match target" {
    const TestData = struct {
        authority: PublicKey,
        value: u64,
    };

    const key1 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const key2 = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

    const data = TestData{
        .authority = key1,
        .value = 100,
    };

    try std.testing.expectError(HasOneError.ConstraintHasOne, validateHasOne(TestData, &data, "authority", &key2));
}

test "validateHasOne works with [32]u8 field type" {
    const TestData = struct {
        authority: [32]u8,
        value: u64,
    };

    const key = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const data = TestData{
        .authority = key.bytes,
        .value = 100,
    };

    try validateHasOne(TestData, &data, "authority", &key);
}

test "validateHasOne fails with [32]u8 field when mismatch" {
    const TestData = struct {
        authority: [32]u8,
        value: u64,
    };

    const key1 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const key2 = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

    const data = TestData{
        .authority = key1.bytes,
        .value = 100,
    };

    try std.testing.expectError(HasOneError.ConstraintHasOne, validateHasOne(TestData, &data, "authority", &key2));
}

test "checkHasOne returns true when matching" {
    const TestData = struct {
        authority: PublicKey,
    };

    const key = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const data = TestData{ .authority = key };

    try std.testing.expect(checkHasOne(TestData, &data, "authority", &key));
}

test "checkHasOne returns false when not matching" {
    const TestData = struct {
        authority: PublicKey,
    };

    const key1 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const key2 = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

    const data = TestData{ .authority = key1 };

    try std.testing.expect(!checkHasOne(TestData, &data, "authority", &key2));
}

test "validateHasOneBytes succeeds with matching bytes" {
    const bytes1 = [_]u8{1} ** 32;
    const bytes2 = [_]u8{1} ** 32;

    try validateHasOneBytes(&bytes1, &bytes2);
}

test "validateHasOneBytes fails with non-matching bytes" {
    const bytes1 = [_]u8{1} ** 32;
    const bytes2 = [_]u8{2} ** 32;

    try std.testing.expectError(HasOneError.ConstraintHasOne, validateHasOneBytes(&bytes1, &bytes2));
}

test "getHasOneFieldBytes returns correct pointer for PublicKey" {
    const TestData = struct {
        authority: PublicKey,
    };

    const key = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const data = TestData{ .authority = key };

    const bytes = getHasOneFieldBytes(TestData, &data, "authority");
    try std.testing.expectEqualSlices(u8, &key.bytes, bytes);
}

test "getHasOneFieldBytes returns correct pointer for [32]u8" {
    const TestData = struct {
        authority: [32]u8,
    };

    const expected = [_]u8{0xAB} ** 32;
    const data = TestData{ .authority = expected };

    const bytes = getHasOneFieldBytes(TestData, &data, "authority");
    try std.testing.expectEqualSlices(u8, &expected, bytes);
}
