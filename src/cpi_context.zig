//! Anchor-style CPI context builder.
//!
//! Rust source: https://github.com/coral-xyz/anchor/blob/master/lang/src/context.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const interface_mod = @import("interface.zig");

const AccountInfo = sol.account.Account.Info;
const Instruction = sol.instruction.Instruction;

/// Remaining account collection errors.
pub const RemainingError = error{
    RemainingAccountsOverflow,
};

fn toAccountInfo(value: anytype) *const AccountInfo {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .pointer) {
        const ChildType = @typeInfo(T).pointer.child;
        if (ChildType == AccountInfo) {
            return value;
        }
        if (@hasDecl(ChildType, "toAccountInfo")) {
            return value.toAccountInfo();
        }
    }
    if (@hasDecl(T, "toAccountInfo")) {
        return value.toAccountInfo();
    }
    @compileError("program must be AccountInfo or type with toAccountInfo()");
}

fn accountInfoFromValue(value: anytype) ?AccountInfo {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .optional) {
        if (value == null) return null;
        return accountInfoFromValue(value.?);
    }
    if (T == AccountInfo) return value;
    if (T == *AccountInfo or T == *const AccountInfo) return value.*;
    if (@hasDecl(T, "toAccountInfo")) return value.toAccountInfo().*;
    @compileError("remaining accounts must provide AccountInfo or toAccountInfo()");
}

fn appendRemainingInfos(list: *std.ArrayList(AccountInfo), remaining: anytype) !void {
    const T = @TypeOf(remaining);
    if (@typeInfo(T) == .optional) {
        if (remaining == null) return;
        return try appendRemainingInfos(list, remaining.?);
    }
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .slice) {
        @compileError("remaining accounts must be a slice");
    }
    for (remaining) |item| {
        if (accountInfoFromValue(item)) |value| {
            try list.append(value);
        }
    }
}

fn appendRemainingInfosInto(
    storage: []AccountInfo,
    len: *usize,
    remaining: anytype,
) !void {
    const T = @TypeOf(remaining);
    if (@typeInfo(T) == .optional) {
        if (remaining == null) return;
        return try appendRemainingInfosInto(storage, len, remaining.?);
    }
    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .slice) {
        @compileError("remaining accounts must be a slice");
    }
    for (remaining) |item| {
        if (accountInfoFromValue(item)) |value| {
            if (len.* >= storage.len) {
                return RemainingError.RemainingAccountsOverflow;
            }
            storage[len.*] = value;
            len.* += 1;
        }
    }
}

/// CPI context builder.
pub fn CpiContext(comptime Program: type, comptime Accounts: type) type {
    return CpiContextWithConfig(Program, Accounts, .{});
}

/// CPI context builder with interface config.
pub fn CpiContextWithConfig(
    comptime Program: type,
    comptime Accounts: type,
    comptime config: interface_mod.InterfaceConfig,
) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        program: *const AccountInfo,
        accounts: Accounts,
        remaining: ?[]const AccountInfo = null,
        remaining_storage: ?[]AccountInfo = null,
        remaining_len: usize = 0,
        remaining_list: std.ArrayList(AccountInfo),
        use_remaining_list: bool = false,
        signer_seeds: ?[]const []const []const u8 = null,

        /// Create a new CPI context.
        pub fn init(allocator: std.mem.Allocator, program: anytype, accounts: Accounts) Self {
            return .{
                .allocator = allocator,
                .program = toAccountInfo(program),
                .accounts = accounts,
                .remaining_list = std.ArrayList(AccountInfo).init(allocator),
            };
        }

        /// Release any memory owned by the context.
        pub fn deinit(self: *Self) void {
            self.remaining_list.deinit();
        }

        fn resolvedRemaining(self: *const Self) ?[]const AccountInfo {
            if (self.remaining_storage) |storage| {
                return storage[0..self.remaining_len];
            }
            if (self.use_remaining_list) {
                return self.remaining_list.items;
            }
            return self.remaining;
        }

        /// Attach remaining accounts.
        pub fn withRemainingAccounts(self: Self, remaining: []const AccountInfo) Self {
            var next = self;
            next.remaining = remaining;
            next.remaining_storage = null;
            next.remaining_len = 0;
            next.use_remaining_list = false;
            next.remaining_list.clearRetainingCapacity();
            return next;
        }

        /// Attach a pre-allocated remaining buffer for pooling.
        pub fn withRemainingStorage(self: Self, storage: []AccountInfo) Self {
            var next = self;
            next.remaining = null;
            next.remaining_storage = storage;
            next.remaining_len = 0;
            next.use_remaining_list = false;
            next.remaining_list.clearRetainingCapacity();
            return next;
        }

        /// Append remaining accounts (auto-collect).
        pub fn appendRemaining(self: *Self, remaining: anytype) !void {
            if (self.remaining_storage) |storage| {
                try appendRemainingInfosInto(storage, &self.remaining_len, remaining);
            } else {
                try appendRemainingInfos(&self.remaining_list, remaining);
                self.use_remaining_list = true;
            }
        }

        /// Reset collected remaining accounts.
        pub fn resetRemaining(self: *Self) void {
            self.remaining_len = 0;
            if (self.use_remaining_list) {
                self.remaining_list.clearRetainingCapacity();
            }
            self.remaining = null;
        }

        /// Attach signer seeds.
        pub fn withSignerSeeds(self: Self, signer_seeds: []const []const []const u8) Self {
            var next = self;
            next.signer_seeds = signer_seeds;
            return next;
        }

        /// Build an instruction without args.
        pub fn instructionNoArgs(self: *const Self, comptime name: []const u8) !Instruction {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.instructionNoArgs(name, self.accounts, self.resolvedRemaining());
        }

        /// Build an instruction without args, providing remaining accounts inline.
        pub fn instructionNoArgsWithRemaining(
            self: *const Self,
            comptime name: []const u8,
            remaining: anytype,
        ) !Instruction {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.instructionNoArgs(name, self.accounts, remaining);
        }

        /// Build an instruction with args.
        pub fn instruction(self: *const Self, comptime name: []const u8, args: anytype) !Instruction {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.instruction(name, self.accounts, args, self.resolvedRemaining());
        }

        /// Build an instruction with args, providing remaining accounts inline.
        pub fn instructionWithRemaining(
            self: *const Self,
            comptime name: []const u8,
            args: anytype,
            remaining: anytype,
        ) !Instruction {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.instruction(name, self.accounts, args, remaining);
        }

        /// Invoke instruction without args.
        pub fn invokeNoArgs(self: *const Self, comptime name: []const u8) !sol.ProgramResult {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            if (self.signer_seeds) |seeds| {
                return try iface.invokeSignedNoArgs(name, self.accounts, self.resolvedRemaining(), seeds);
            }
            return try iface.invokeNoArgs(name, self.accounts, self.resolvedRemaining());
        }

        /// Invoke instruction without args, providing remaining accounts inline.
        pub fn invokeNoArgsWithRemaining(
            self: *const Self,
            comptime name: []const u8,
            remaining: anytype,
        ) !sol.ProgramResult {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            if (self.signer_seeds) |seeds| {
                return try iface.invokeSignedNoArgs(name, self.accounts, remaining, seeds);
            }
            return try iface.invokeNoArgs(name, self.accounts, remaining);
        }

        /// Clear, append remaining accounts, then invoke without args.
        pub fn invokeNoArgsWithRemainingReset(
            self: *Self,
            comptime name: []const u8,
            remaining: anytype,
        ) !sol.ProgramResult {
            self.resetRemaining();
            try self.appendRemaining(remaining);
            return try self.invokeNoArgs(name);
        }

        /// Invoke instruction with args.
        pub fn invoke(self: *const Self, comptime name: []const u8, args: anytype) !sol.ProgramResult {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            if (self.signer_seeds) |seeds| {
                return try iface.invokeSigned(name, self.accounts, args, self.resolvedRemaining(), seeds);
            }
            return try iface.invoke(name, self.accounts, args, self.resolvedRemaining());
        }

        /// Invoke instruction with args, providing remaining accounts inline.
        pub fn invokeWithRemaining(
            self: *const Self,
            comptime name: []const u8,
            args: anytype,
            remaining: anytype,
        ) !sol.ProgramResult {
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            if (self.signer_seeds) |seeds| {
                return try iface.invokeSigned(name, self.accounts, args, remaining, seeds);
            }
            return try iface.invoke(name, self.accounts, args, remaining);
        }

        /// Clear, append remaining accounts, then invoke with args and signer seeds.
        pub fn invokeWithRemainingResetSigned(
            self: *Self,
            comptime name: []const u8,
            args: anytype,
            remaining: anytype,
            signer_seeds: []const []const []const u8,
        ) !sol.ProgramResult {
            self.resetRemaining();
            try self.appendRemaining(remaining);
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.invokeSigned(name, self.accounts, args, self.resolvedRemaining(), signer_seeds);
        }

        /// Clear, append remaining accounts, then invoke without args and signer seeds.
        pub fn invokeNoArgsWithRemainingResetSigned(
            self: *Self,
            comptime name: []const u8,
            remaining: anytype,
            signer_seeds: []const []const []const u8,
        ) !sol.ProgramResult {
            self.resetRemaining();
            try self.appendRemaining(remaining);
            var iface = try interface_mod.Interface(Program, config).init(
                self.allocator,
                self.program.id.*,
            );
            return try iface.invokeSignedNoArgs(name, self.accounts, self.resolvedRemaining(), signer_seeds);
        }

        /// Clear, append remaining accounts, then invoke with args.
        pub fn invokeWithRemainingReset(
            self: *Self,
            comptime name: []const u8,
            args: anytype,
            remaining: anytype,
        ) !sol.ProgramResult {
            self.resetRemaining();
            try self.appendRemaining(remaining);
            return try self.invoke(name, args);
        }
    };
}

test "CpiContext builds instruction" {
    const TestAccounts = struct {
        payer: *const AccountInfo,
    };

    const TestProgram = struct {
        pub const instructions = struct {
            pub const ping = @import("idl.zig").Instruction(.{
                .Accounts = TestAccounts,
                .Args = void,
            });
        };
    };

    var program_id = sol.PublicKey.default();
    var owner = sol.PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;
    const program_info = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    const payer_info = program_info;
    const accounts = TestAccounts{ .payer = &payer_info };

    var ctx = CpiContext(TestProgram, TestAccounts).init(std.testing.allocator, &program_info, accounts);
    defer ctx.deinit();
    const ix = try ctx.instructionNoArgs("ping");
    defer ix.deinit(std.testing.allocator);
    try std.testing.expect(ix.data_len == 8);
}

test "CpiContext builds instruction with inline remaining accounts" {
    const TestAccounts = struct {
        payer: *const AccountInfo,
    };

    const TestProgram = struct {
        pub const instructions = struct {
            pub const ping = @import("idl.zig").Instruction(.{
                .Accounts = TestAccounts,
                .Args = void,
            });
        };
    };

    var program_id = sol.PublicKey.default();
    var owner = sol.PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;
    const program_info = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    var rem_id = sol.PublicKey.default();
    var rem_owner = sol.PublicKey.default();
    var rem_lamports: u64 = 1;
    var rem_data: [0]u8 = undefined;
    const rem_info = AccountInfo{
        .id = &rem_id,
        .owner_id = &rem_owner,
        .lamports = &rem_lamports,
        .data_len = 0,
        .data = &rem_data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const accounts = TestAccounts{ .payer = &program_info };
    var ctx = CpiContext(TestProgram, TestAccounts).init(std.testing.allocator, &program_info, accounts);
    defer ctx.deinit();
    const remaining = [_]*const AccountInfo{ &rem_info };
    const ix = try ctx.instructionNoArgsWithRemaining("ping", remaining[0..]);
    defer ix.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
}

test "CpiContext collects remaining accounts with storage pool" {
    const TestAccounts = struct {
        payer: *const AccountInfo,
    };

    const TestProgram = struct {
        pub const instructions = struct {
            pub const ping = @import("idl.zig").Instruction(.{
                .Accounts = TestAccounts,
                .Args = void,
            });
        };
    };

    var program_id = sol.PublicKey.default();
    var owner = sol.PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;
    const program_info = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    var rem_id = sol.PublicKey.default();
    var rem_owner = sol.PublicKey.default();
    var rem_lamports: u64 = 1;
    var rem_data: [0]u8 = undefined;
    const rem_info = AccountInfo{
        .id = &rem_id,
        .owner_id = &rem_owner,
        .lamports = &rem_lamports,
        .data_len = 0,
        .data = &rem_data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const accounts = TestAccounts{ .payer = &program_info };
    var ctx = CpiContext(TestProgram, TestAccounts).init(std.testing.allocator, &program_info, accounts);
    defer ctx.deinit();

    var storage: [2]AccountInfo = undefined;
    ctx = ctx.withRemainingStorage(storage[0..]);
    try ctx.appendRemaining(&[_]*const AccountInfo{ &rem_info });
    const ix = try ctx.instructionNoArgs("ping");
    defer ix.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
}

test "CpiContext resetRemaining clears collection" {
    const TestAccounts = struct {
        payer: *const AccountInfo,
    };

    const TestProgram = struct {
        pub const instructions = struct {
            pub const ping = @import("idl.zig").Instruction(.{
                .Accounts = TestAccounts,
                .Args = void,
            });
        };
    };

    var program_id = sol.PublicKey.default();
    var owner = sol.PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;
    const program_info = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    var rem_id = sol.PublicKey.default();
    var rem_owner = sol.PublicKey.default();
    var rem_lamports: u64 = 1;
    var rem_data: [0]u8 = undefined;
    const rem_info = AccountInfo{
        .id = &rem_id,
        .owner_id = &rem_owner,
        .lamports = &rem_lamports,
        .data_len = 0,
        .data = &rem_data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const accounts = TestAccounts{ .payer = &program_info };
    var ctx = CpiContext(TestProgram, TestAccounts).init(std.testing.allocator, &program_info, accounts);
    defer ctx.deinit();

    try ctx.appendRemaining(&[_]*const AccountInfo{ &rem_info });
    ctx.resetRemaining();
    try ctx.appendRemaining(&[_]*const AccountInfo{ &rem_info });
    const ix = try ctx.instructionNoArgs("ping");
    defer ix.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
}

test "CpiContext invokeWithRemainingResetSigned uses inline seeds" {
    const TestAccounts = struct {
        payer: *const AccountInfo,
    };

    const TestProgram = struct {
        pub const instructions = struct {
            pub const ping = @import("idl.zig").Instruction(.{
                .Accounts = TestAccounts,
                .Args = void,
            });
        };
    };

    var program_id = sol.PublicKey.default();
    var owner = sol.PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;
    const program_info = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    var rem_id = sol.PublicKey.default();
    var rem_owner = sol.PublicKey.default();
    var rem_lamports: u64 = 1;
    var rem_data: [0]u8 = undefined;
    const rem_info = AccountInfo{
        .id = &rem_id,
        .owner_id = &rem_owner,
        .lamports = &rem_lamports,
        .data_len = 0,
        .data = &rem_data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const accounts = TestAccounts{ .payer = &program_info };
    var ctx = CpiContext(TestProgram, TestAccounts).init(std.testing.allocator, &program_info, accounts);
    defer ctx.deinit();
    const remaining = [_]*const AccountInfo{ &rem_info };
    const signer_seeds: []const []const []const u8 = &.{&.{ "seed" }};
    _ = try ctx.invokeNoArgsWithRemainingResetSigned("ping", remaining[0..], signer_seeds);
}
