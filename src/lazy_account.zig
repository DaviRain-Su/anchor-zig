//! Zig implementation of Anchor LazyAccount.
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/lazy_account.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;
const Discriminator = discriminator_mod.Discriminator;
const DISCRIMINATOR_LENGTH = discriminator_mod.DISCRIMINATOR_LENGTH;
const BorshError = sol.borsh.BorshError;

/// LazyAccount configuration
pub const LazyAccountConfig = struct {
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

/// LazyAccount loads and caches account data on demand.
pub fn LazyAccount(comptime T: type, comptime config: LazyAccountConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,
        cached: ?T = null,

        pub const DataType = T;
        pub const DISCRIMINATOR: ?Discriminator = config.discriminator;
        pub const OWNER: ?PublicKey = config.owner;
        pub const ADDRESS: ?PublicKey = config.address;
        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        /// Initialize a LazyAccount without loading data.
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

            return Self{ .info = info };
        }

        /// Access the account data, loading and caching on first access.
        pub fn get(self: *Self) !*T {
            if (self.cached == null) {
                _ = try self.reload();
            }
            return &self.cached.?;
        }

        /// Reload the account data from bytes and overwrite the cache.
        pub fn reload(self: *Self) !*T {
            const offset = if (config.discriminator != null) DISCRIMINATOR_LENGTH else 0;
            const data_slice = self.info.data[offset..self.info.data_len];
            const value = try sol.borsh.deserializeExact(T, data_slice);
            self.cached = value;
            return &self.cached.?;
        }

        /// Serialize cached data back into account bytes.
        pub fn save(self: *Self) BorshError!void {
            if (self.cached == null) return;
            const offset = if (config.discriminator != null) DISCRIMINATOR_LENGTH else 0;
            const data_slice = self.info.data[offset..self.info.data_len];
            _ = try sol.borsh.serialize(T, self.cached.?, data_slice);
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

test "LazyAccount loads on demand and caches data" {
    const Data = struct {
        value: u64,
        flag: bool,
    };
    const disc = discriminator_mod.accountDiscriminator("Lazy");
    const Lazy = LazyAccount(Data, .{ .discriminator = disc });

    var owner = PublicKey.default();
    var key = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 = undefined;
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &disc);
    _ = try sol.borsh.serialize(Data, .{ .value = 9, .flag = true }, buffer[DISCRIMINATOR_LENGTH..]);

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

    var lazy = try Lazy.load(&info);
    const loaded = try lazy.get();
    try std.testing.expectEqual(@as(u64, 9), loaded.value);
    try std.testing.expect(loaded.flag);
}

test "LazyAccount saves cached data" {
    const Data = struct {
        count: u32,
    };
    const disc = discriminator_mod.accountDiscriminator("LazySave");
    const Lazy = LazyAccount(Data, .{ .discriminator = disc });

    var owner = PublicKey.default();
    var key = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 = undefined;
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &disc);
    _ = try sol.borsh.serialize(Data, .{ .count = 1 }, buffer[DISCRIMINATOR_LENGTH..]);

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

    var lazy = try Lazy.load(&info);
    const data = try lazy.get();
    data.count = 7;
    try lazy.save();

    const decoded = try sol.borsh.deserializeExact(Data, buffer[DISCRIMINATOR_LENGTH..]);
    try std.testing.expectEqual(@as(u32, 7), decoded.count);
}
