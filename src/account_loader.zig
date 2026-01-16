//! Zig implementation of Anchor AccountLoader (zero-copy access).
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/account_loader.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;
const Discriminator = discriminator_mod.Discriminator;
const DISCRIMINATOR_LENGTH = discriminator_mod.DISCRIMINATOR_LENGTH;

/// AccountLoader configuration
pub const AccountLoaderConfig = struct {
    /// Optional discriminator to validate (8 bytes)
    discriminator: ?Discriminator = null,
    /// Optional owner program id
    owner: ?PublicKey = null,
    /// Optional account address
    address: ?PublicKey = null,
    /// Require writable account
    mut: bool = false,
    /// Require signer account
    signer: bool = false,
};

/// Zero-copy account loader
pub fn AccountLoader(comptime T: type, comptime config: AccountLoaderConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,
        data: *T,

        pub const DataType = T;
        pub const DISCRIMINATOR: ?Discriminator = config.discriminator;
        pub const OWNER: ?PublicKey = config.owner;
        pub const ADDRESS: ?PublicKey = config.address;
        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        /// Load account with optional discriminator/owner/address checks.
        pub fn load(info: *const AccountInfo) !Self {
            if (config.owner) |expected_owner| {
                if (!info.owner_id.equals(expected_owner)) {
                    return error.ConstraintOwner;
                }
            }
            if (config.address) |expected_address| {
                if (!info.id.equals(expected_address)) {
                    return error.ConstraintAddress;
                }
            }
            if (config.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }
            if (config.signer and info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            const offset = if (config.discriminator != null) DISCRIMINATOR_LENGTH else 0;
            if (info.data_len < offset + @sizeOf(T)) {
                return error.AccountDiscriminatorNotFound;
            }

            if (config.discriminator) |expected| {
                const data_slice = info.data[0..DISCRIMINATOR_LENGTH];
                if (!std.mem.eql(u8, data_slice, &expected)) {
                    return error.AccountDiscriminatorMismatch;
                }
            }

            const data_ptr: *T = @ptrCast(@alignCast(info.data + offset));
            return Self{ .info = info, .data = data_ptr };
        }

        /// Load account without discriminator validation.
        pub fn loadUnchecked(info: *const AccountInfo) !Self {
            const offset = if (config.discriminator != null) DISCRIMINATOR_LENGTH else 0;
            if (info.data_len < offset + @sizeOf(T)) {
                return error.AccountDiscriminatorNotFound;
            }
            const data_ptr: *T = @ptrCast(@alignCast(info.data + offset));
            return Self{ .info = info, .data = data_ptr };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

test "AccountLoader loads zero-copy account data" {
    const Data = struct {
        value: u64,
        flag: bool,
    };
    const disc = discriminator_mod.accountDiscriminator("Loader");

    const Loader = AccountLoader(Data, .{ .discriminator = disc });

    var owner = PublicKey.default();
    var key = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 = undefined;
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &disc);
    const data_ptr: *Data = @ptrCast(@alignCast(buffer[DISCRIMINATOR_LENGTH..].ptr));
    data_ptr.* = .{ .value = 42, .flag = true };

    const info = AccountInfo{
        .id = &key,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const loaded = try Loader.load(&info);
    try std.testing.expectEqual(@as(u64, 42), loaded.data.value);
    try std.testing.expect(loaded.data.flag);
}
