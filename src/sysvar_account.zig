//! Sysvar account wrappers for Anchor-style account validation.
//!
//! Rust source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/sysvar.rs

const std = @import("std");
const sol = @import("solana_program_sdk");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;

/// Sysvar marker for ID-only sysvars without a data type.
pub fn SysvarId(comptime sysvar_id: PublicKey) type {
    return struct {
        pub const id = sysvar_id;
    };
}


const EPOCH_SCHEDULE_ID = PublicKey.comptimeFromBase58("SysvarEpochSchedu1e111111111111111111111111");

pub const Instructions = SysvarId(sol.INSTRUCTIONS_ID);
pub const StakeHistory = SysvarId(sol.STAKE_HISTORY_ID);

pub const ClockData = SysvarData(sol.clock.Clock);
pub const RentData = SysvarData(sol.rent.Rent.Data);
pub const EpochScheduleData = SysvarDataId(EPOCH_SCHEDULE_ID, sol.epoch_schedule.EpochSchedule);
pub const SlotHashesData = SysvarData(sol.slot_hashes.SlotHashes);
pub const SlotHistoryData = SysvarData(sol.slot_history.SlotHistory);
pub const EpochRewardsData = SysvarDataId(sol.EPOCH_REWARDS_ID, sol.epoch_rewards.EpochRewards);
pub const LastRestartSlotData = SysvarDataId(sol.LAST_RESTART_SLOT_ID, sol.last_restart_slot.LastRestartSlot);

pub const ClockSysvar = SysvarId(sol.CLOCK_ID);
pub const RentSysvar = SysvarId(sol.RENT_ID);
pub const EpochScheduleSysvar = SysvarId(EPOCH_SCHEDULE_ID);
pub const SlotHashesSysvar = SysvarId(sol.SLOT_HASHES_ID);
pub const SlotHistorySysvar = SysvarId(sol.SLOT_HISTORY_ID);
pub const EpochRewardsSysvar = SysvarId(sol.EPOCH_REWARDS_ID);
pub const LastRestartSlotSysvar = SysvarId(sol.LAST_RESTART_SLOT_ID);

/// Sysvar account wrapper with address validation.
pub fn Sysvar(comptime SysvarType: type) type {
    if (!@hasDecl(SysvarType, "id")) {
        @compileError("Sysvar type must define an id");
    }

    return struct {
        const Self = @This();

        pub const SYSVAR_TYPE = SysvarType;
        pub const ID = SysvarType.id;

        info: *const AccountInfo,

        pub fn load(info: *const AccountInfo) !Self {
            if (!info.id.equals(SysvarType.id)) {
                return error.ConstraintAddress;
            }
            return .{ .info = info };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Sysvar account wrapper with data parsing.
///
/// Reads the sysvar data into the provided type and validates the address.

/// Sysvar account wrapper with data parsing for types without an embedded id.
///
/// Reads the sysvar data into the provided type and validates the address.
pub fn SysvarDataId(comptime sysvar_id: PublicKey, comptime SysvarType: type) type {
    return struct {
        const Self = @This();

        pub const SYSVAR_TYPE = SysvarType;
        pub const ID = sysvar_id;

        info: *const AccountInfo,
        data: SysvarType,

        pub fn load(info: *const AccountInfo) !Self {
            if (!info.id.equals(sysvar_id)) {
                return error.ConstraintAddress;
            }
            if (info.data_len < @sizeOf(SysvarType)) {
                return error.AccountDidNotDeserialize;
            }
            const bytes = info.data[0..@sizeOf(SysvarType)];
            const value = std.mem.bytesToValue(SysvarType, bytes);
            return .{ .info = info, .data = value };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

pub fn SysvarData(comptime SysvarType: type) type {
    if (!@hasDecl(SysvarType, "id")) {
        @compileError("Sysvar type must define an id");
    }

    return struct {
        const Self = @This();

        pub const SYSVAR_TYPE = SysvarType;
        pub const ID = SysvarType.id;

        info: *const AccountInfo,
        data: SysvarType,

        pub fn load(info: *const AccountInfo) !Self {
            if (!info.id.equals(SysvarType.id)) {
                return error.ConstraintAddress;
            }
            if (info.data_len < @sizeOf(SysvarType)) {
                return error.AccountDidNotDeserialize;
            }
            const bytes = info.data[0..@sizeOf(SysvarType)];
            const value = std.mem.bytesToValue(SysvarType, bytes);
            return .{ .info = info, .data = value };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

test "SysvarData load parses data" {
    const DummySysvar = extern struct {
        pub const id = PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
        value: u64,
    };

    var id = DummySysvar.id;
    var owner = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [@sizeOf(DummySysvar)]u8 = undefined;
    const expected = DummySysvar{ .value = 42 };
    std.mem.writeInt(u64, buffer[0..8], expected.value, .little);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const Wrapper = SysvarData(DummySysvar);
    const loaded = try Wrapper.load(&info);
    try std.testing.expectEqual(@as(u64, 42), loaded.data.value);
}
