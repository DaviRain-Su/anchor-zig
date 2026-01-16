//! Zig implementation of Anchor interface and CPI helpers.
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/interface.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;
const AccountMeta = sol.instruction.AccountMeta;
const Instruction = sol.instruction.Instruction;
const AccountParam = sol.account.Account.Param;

const Discriminator = discriminator_mod.Discriminator;
const DISCRIMINATOR_LENGTH = discriminator_mod.DISCRIMINATOR_LENGTH;

/// Interface validation config
pub const InterfaceConfig = struct {
    program_ids: ?[]const PublicKey = null,
    meta_merge: MetaMergeStrategy = .keep_all,
};

/// Strategy for handling duplicate AccountMeta entries.
pub const MetaMergeStrategy = enum {
    keep_all,
    merge_duplicates,
    error_on_conflict,
};

/// Interface program account type with multiple allowed IDs.
pub fn InterfaceProgram(comptime program_ids: []const PublicKey) type {
    if (program_ids.len == 0) {
        @compileError("InterfaceProgram requires at least one program id");
    }

    return struct {
        const Self = @This();

        info: *const AccountInfo,

        pub const IDS = program_ids;

        pub fn load(info: *const AccountInfo) !Self {
            if (info.is_executable == 0) {
                return error.ConstraintExecutable;
            }
            if (!isAllowedProgramId(program_ids, info.id.*)) {
                return error.InvalidProgramId;
            }
            return Self{ .info = info };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Interface program account type that accepts any executable program ID.
pub const InterfaceProgramAny = struct {
    info: *const AccountInfo,

    pub fn load(info: *const AccountInfo) !InterfaceProgramAny {
        if (info.is_executable == 0) {
            return error.ConstraintExecutable;
        }
        return .{ .info = info };
    }

    pub fn key(self: InterfaceProgramAny) *const PublicKey {
        return self.info.id;
    }

    pub fn toAccountInfo(self: InterfaceProgramAny) *const AccountInfo {
        return self.info;
    }
};

/// Interface program account type with no validation.
pub const InterfaceProgramUnchecked = struct {
    info: *const AccountInfo,

    pub fn load(info: *const AccountInfo) !InterfaceProgramUnchecked {
        return .{ .info = info };
    }

    pub fn key(self: InterfaceProgramUnchecked) *const PublicKey {
        return self.info.id;
    }

    pub fn toAccountInfo(self: InterfaceProgramUnchecked) *const AccountInfo {
        return self.info;
    }
};

/// Interface account configuration.
pub const InterfaceAccountConfig = struct {
    discriminator: ?Discriminator = null,
    owners: ?[]const PublicKey = null,
    address: ?PublicKey = null,
    executable: bool = false,
    rent_exempt: bool = false,
    mut: bool = false,
    signer: bool = false,
};

/// Interface account info configuration (no data validation).
pub const InterfaceAccountInfoConfig = struct {
    owners: ?[]const PublicKey = null,
    address: ?PublicKey = null,
    executable: bool = false,
    rent_exempt: bool = false,
    mut: bool = false,
    signer: bool = false,
};

/// Override AccountMeta flags for CPI when AccountInfo flags differ.
pub const AccountMetaOverride = struct {
    info: *const AccountInfo,
    is_signer: ?bool = null,
    is_writable: ?bool = null,

    pub fn init(info: *const AccountInfo) AccountMetaOverride {
        return .{ .info = info };
    }

    pub fn toAccountMeta(self: AccountMetaOverride) AccountMeta {
        const signer = self.is_signer orelse (self.info.is_signer != 0);
        const writable = self.is_writable orelse (self.info.is_writable != 0);
        return AccountMeta.init(self.info.id.*, signer, writable);
    }

    pub fn toAccountInfo(self: AccountMetaOverride) *const AccountInfo {
        return self.info;
    }
};

/// Interface account wrapper that accepts multiple owner programs.
pub fn InterfaceAccount(comptime T: type, comptime config: InterfaceAccountConfig) type {
    if (config.owners) |owners| {
        if (owners.len == 0) {
            @compileError("InterfaceAccount owners cannot be empty");
        }
    }

    return struct {
        const Self = @This();

        info: *const AccountInfo,
        data: *T,

        pub const DataType = T;
        pub const DISCRIMINATOR: ?Discriminator = config.discriminator;
        pub const OWNERS: ?[]const PublicKey = config.owners;
        pub const ADDRESS: ?PublicKey = config.address;
        pub const HAS_EXECUTABLE: bool = config.executable;
        pub const HAS_RENT_EXEMPT: bool = config.rent_exempt;
        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        pub fn load(info: *const AccountInfo) !Self {
            try validateAccess(
                info,
                config.owners,
                config.address,
                config.executable,
                config.rent_exempt,
                config.mut,
                config.signer,
            );

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

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Interface account wrapper for raw AccountInfo (no data validation).
pub fn InterfaceAccountInfo(comptime config: InterfaceAccountInfoConfig) type {
    if (config.owners) |owners| {
        if (owners.len == 0) {
            @compileError("InterfaceAccountInfo owners cannot be empty");
        }
    }

    return struct {
        const Self = @This();

        info: *const AccountInfo,

        pub const OWNERS: ?[]const PublicKey = config.owners;
        pub const ADDRESS: ?PublicKey = config.address;
        pub const HAS_EXECUTABLE: bool = config.executable;
        pub const HAS_RENT_EXEMPT: bool = config.rent_exempt;
        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        pub fn load(info: *const AccountInfo) !Self {
            try validateAccess(
                info,
                config.owners,
                config.address,
                config.executable,
                config.rent_exempt,
                config.mut,
                config.signer,
            );
            return Self{ .info = info };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// CPI interface builder for programs without fixed IDs.
pub fn Interface(comptime Program: type, comptime config: InterfaceConfig) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        program_id: PublicKey,

        pub fn init(allocator: std.mem.Allocator, program_id: PublicKey) !Self {
            if (config.program_ids) |ids| {
                if (!isAllowedProgramId(ids, program_id)) {
                    return error.InvalidProgramId;
                }
            }
            return Self{ .allocator = allocator, .program_id = program_id };
        }

        pub fn instructionNoArgs(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
        ) !Instruction {
            const instr = getInstructionType(name);
            if (instr.Args != void) {
                @compileError("instructionNoArgs used with non-void Args");
            }
            return try buildInstruction(self, name, accounts, null, null);
        }

        pub fn instruction(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
        ) !Instruction {
            const instr = getInstructionType(name);
            if (instr.Args == void) {
                @compileError("instruction used with void Args; use instructionNoArgs");
            }
            if (@TypeOf(args) != instr.Args) {
                @compileError("instruction args must match instruction Args");
            }
            return try buildInstruction(self, name, accounts, args, null);
        }

        pub fn instructionNoArgsWithRemaining(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            remaining: anytype,
        ) !Instruction {
            const instr = getInstructionType(name);
            if (instr.Args != void) {
                @compileError("instructionNoArgsWithRemaining used with non-void Args");
            }
            return try buildInstruction(self, name, accounts, null, remaining);
        }

        pub fn instructionWithRemaining(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
            remaining: anytype,
        ) !Instruction {
            const instr = getInstructionType(name);
            if (instr.Args == void) {
                @compileError("instructionWithRemaining used with void Args; use instructionNoArgsWithRemaining");
            }
            if (@TypeOf(args) != instr.Args) {
                @compileError("instruction args must match instruction Args");
            }
            return try buildInstruction(self, name, accounts, args, remaining);
        }

        pub fn invokeNoArgs(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            remaining: anytype,
        ) !sol.ProgramResult {
            const instr = getInstructionType(name);
            if (instr.Args != void) {
                @compileError("invokeNoArgs used with non-void Args");
            }
            return try invokeInternal(self, name, accounts, null, remaining, null);
        }

        pub fn invoke(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
            remaining: anytype,
        ) !sol.ProgramResult {
            const instr = getInstructionType(name);
            if (instr.Args == void) {
                @compileError("invoke used with void Args; use invokeNoArgs");
            }
            if (@TypeOf(args) != instr.Args) {
                @compileError("invoke args must match instruction Args");
            }
            return try invokeInternal(self, name, accounts, args, remaining, null);
        }

        pub fn invokeSignedNoArgs(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            remaining: anytype,
            signer_seeds: []const []const []const u8,
        ) !sol.ProgramResult {
            const instr = getInstructionType(name);
            if (instr.Args != void) {
                @compileError("invokeSignedNoArgs used with non-void Args");
            }
            return try invokeInternal(self, name, accounts, null, remaining, signer_seeds);
        }

        pub fn invokeSigned(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
            remaining: anytype,
            signer_seeds: []const []const []const u8,
        ) !sol.ProgramResult {
            const instr = getInstructionType(name);
            if (instr.Args == void) {
                @compileError("invokeSigned used with void Args; use invokeSignedNoArgs");
            }
            if (@TypeOf(args) != instr.Args) {
                @compileError("invokeSigned args must match instruction Args");
            }
            return try invokeInternal(self, name, accounts, args, remaining, signer_seeds);
        }

        fn getInstructionType(comptime name: []const u8) type {
            if (!@hasDecl(Program, "instructions")) {
                @compileError("Program is missing instructions");
            }
            if (!@hasField(Program.instructions, name)) {
                @compileError("Program is missing instruction: " ++ name);
            }
            return @field(Program.instructions, name);
        }

        fn buildInstruction(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
            remaining: anytype,
        ) !Instruction {
            const instr = getInstructionType(name);
            if (@TypeOf(accounts) != instr.Accounts) {
                @compileError("instruction accounts must match instruction Accounts");
            }

            var metas = std.ArrayList(AccountMeta).init(self.allocator);
            defer metas.deinit();
            try buildAccountMetas(instr.Accounts, accounts, &metas);
            try appendRemainingAccounts(&metas, remaining);
            try applyMetaMerge(self.allocator, config.meta_merge, &metas);

            const disc = discriminator_mod.instructionDiscriminator(name);
            if (instr.Args == void) {
                return Instruction.newWithBytes(self.allocator, self.program_id, disc[0..], metas.items);
            }

            const args_bytes = try sol.borsh.serializeAlloc(self.allocator, instr.Args, args);
            defer self.allocator.free(args_bytes);
            var data = try self.allocator.alloc(u8, DISCRIMINATOR_LENGTH + args_bytes.len);
            defer self.allocator.free(data);
            @memcpy(data[0..DISCRIMINATOR_LENGTH], &disc);
            @memcpy(data[DISCRIMINATOR_LENGTH..], args_bytes);
            return Instruction.newWithBytes(self.allocator, self.program_id, data, metas.items);
        }

        fn invokeInternal(
            self: *Self,
            comptime name: []const u8,
            accounts: anytype,
            args: anytype,
            remaining: anytype,
            signer_seeds: ?[]const []const []const u8,
        ) !sol.ProgramResult {
            if (!@hasDecl(Instruction, "invoke") or !@hasDecl(Instruction, "from")) {
                @compileError("Interface invoke helpers require solana_program_sdk.instruction.Instruction");
            }

            const instr = getInstructionType(name);
            if (@TypeOf(accounts) != instr.Accounts) {
                @compileError("invoke accounts must match instruction Accounts");
            }

            var metas = std.ArrayList(AccountMeta).init(self.allocator);
            defer metas.deinit();
            try buildAccountMetas(instr.Accounts, accounts, &metas);
            try appendRemainingAccounts(&metas, remaining);
            try applyMetaMerge(self.allocator, config.meta_merge, &metas);

            var params = std.ArrayList(AccountParam).init(self.allocator);
            defer params.deinit();
            try params.ensureTotalCapacity(metas.items.len);
            for (metas.items, 0..) |_, i| {
                params.appendAssumeCapacity(sol.instruction.accountMetaToParam(&metas.items[i]));
            }

            var infos = std.ArrayList(AccountInfo).init(self.allocator);
            defer infos.deinit();
            try buildAccountInfos(instr.Accounts, accounts, &infos);
            try appendRemainingAccountInfos(&infos, remaining);
            try applyInfoMerge(self.allocator, config.meta_merge, &metas, &infos);

            const disc = discriminator_mod.instructionDiscriminator(name);
            if (instr.Args == void) {
                const cpi = Instruction.from(.{
                    .program_id = &self.program_id,
                    .accounts = params.items,
                    .data = disc[0..],
                });
                if (signer_seeds) |seeds| {
                    return cpi.invokeSigned(infos.items, seeds);
                }
                return cpi.invoke(infos.items);
            }

            const args_bytes = try sol.borsh.serializeAlloc(self.allocator, instr.Args, args);
            defer self.allocator.free(args_bytes);
            const data = try self.allocator.alloc(u8, DISCRIMINATOR_LENGTH + args_bytes.len);
            defer self.allocator.free(data);
            @memcpy(data[0..DISCRIMINATOR_LENGTH], &disc);
            @memcpy(data[DISCRIMINATOR_LENGTH..], args_bytes);

            const cpi = Instruction.from(.{
                .program_id = &self.program_id,
                .accounts = params.items,
                .data = data,
            });
            if (signer_seeds) |seeds| {
                return cpi.invokeSigned(infos.items, seeds);
            }
            return cpi.invoke(infos.items);
        }
    };
}

fn applyMetaMerge(
    allocator: std.mem.Allocator,
    strategy: MetaMergeStrategy,
    metas: *std.ArrayList(AccountMeta),
) !void {
    if (strategy == .keep_all) return;

    var merged = std.ArrayList(AccountMeta).init(allocator);
    defer merged.deinit();

    var seen = std.AutoHashMap([PublicKey.length]u8, usize).init(allocator);
    defer seen.deinit();

    for (metas.items) |meta| {
        if (seen.get(meta.pubkey.bytes)) |index| {
            const existing = merged.items[index];
            const conflict = (meta.is_signer != existing.is_signer) or (meta.is_writable != existing.is_writable);
            if (strategy == .error_on_conflict and conflict) {
                return error.DuplicateAccountMeta;
            }
            merged.items[index].is_signer = existing.is_signer or meta.is_signer;
            merged.items[index].is_writable = existing.is_writable or meta.is_writable;
            continue;
        }
        try seen.put(meta.pubkey.bytes, merged.items.len);
        try merged.append(meta);
    }

    metas.clearRetainingCapacity();
    try metas.appendSlice(merged.items);
}

fn applyInfoMerge(
    allocator: std.mem.Allocator,
    strategy: MetaMergeStrategy,
    metas: *const std.ArrayList(AccountMeta),
    infos: *std.ArrayList(AccountInfo),
) !void {
    if (strategy == .keep_all) return;

    var merged = std.ArrayList(AccountInfo).init(allocator);
    defer merged.deinit();

    var seen = std.AutoHashMap([PublicKey.length]u8, void).init(allocator);
    defer seen.deinit();

    for (metas.items) |meta| {
        if (seen.contains(meta.pubkey.bytes)) continue;
        var found = false;
        for (infos.items) |info| {
            if (info.id.equals(meta.pubkey)) {
                try merged.append(info);
                try seen.put(meta.pubkey.bytes, {});
                found = true;
                break;
            }
        }
        if (!found) {
            return error.MissingAccountInfo;
        }
    }

    infos.clearRetainingCapacity();
    try infos.appendSlice(merged.items);
}

fn buildAccountMetas(
    comptime Accounts: type,
    accounts: Accounts,
    metas: *std.ArrayList(AccountMeta),
) !void {
    const fields = @typeInfo(Accounts).@"struct".fields;
    inline for (fields) |field| {
        const value = @field(accounts, field.name);
        if (try accountMetaFromValue(value)) |meta| {
            try metas.append(meta);
        }
    }
}

fn buildAccountInfos(
    comptime Accounts: type,
    accounts: Accounts,
    infos: *std.ArrayList(AccountInfo),
) !void {
    const fields = @typeInfo(Accounts).@"struct".fields;
    inline for (fields) |field| {
        const value = @field(accounts, field.name);
        if (try accountInfoValueFromValue(value)) |info| {
            try infos.append(info);
        }
    }
}

fn appendRemainingAccounts(metas: *std.ArrayList(AccountMeta), remaining: anytype) !void {
    const T = @TypeOf(remaining);
    if (@typeInfo(T) == .optional) {
        if (remaining == null) return;
        return try appendRemainingAccounts(metas, remaining.?);
    }

    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .slice) {
        @compileError("remaining accounts must be a slice");
    }
    for (remaining) |item| {
        if (try accountMetaFromValue(item)) |meta| {
            try metas.append(meta);
        }
    }
}

fn appendRemainingAccountInfos(infos: *std.ArrayList(AccountInfo), remaining: anytype) !void {
    const T = @TypeOf(remaining);
    if (@typeInfo(T) == .optional) {
        if (remaining == null) return;
        return try appendRemainingAccountInfos(infos, remaining.?);
    }

    const info = @typeInfo(T);
    if (info != .pointer or info.pointer.size != .slice) {
        @compileError("remaining accounts must be a slice");
    }

    for (remaining) |item| {
        if (try accountInfoValueFromValue(item)) |value| {
            try infos.append(value);
        }
    }
}

fn accountMetaFromValue(value: anytype) !?AccountMeta {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .optional) {
        if (value == null) return null;
        return try accountMetaFromValue(value.?);
    }
    if (@hasDecl(T, "toAccountMeta")) {
        return value.toAccountMeta();
    }
    if (T == AccountMeta) {
        return value;
    }
    if (T == *const AccountMeta or T == *AccountMeta) {
        return value.*;
    }
    if (T == AccountInfo) {
        return AccountMeta.init(value.id.*, value.is_signer != 0, value.is_writable != 0);
    }
    if (T == *AccountInfo) {
        return AccountMeta.init(value.id.*, value.is_signer != 0, value.is_writable != 0);
    }
    if (T == *const AccountInfo) {
        return AccountMeta.init(value.id.*, value.is_signer != 0, value.is_writable != 0);
    }
    if (@hasDecl(T, "toAccountInfo")) {
        const info_ptr = value.toAccountInfo();
        return AccountMeta.init(info_ptr.id.*, info_ptr.is_signer != 0, info_ptr.is_writable != 0);
    }
    @compileError("interface accounts must provide AccountMeta, AccountInfo, or toAccountInfo()");
}

fn accountInfoValueFromValue(value: anytype) !?AccountInfo {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .optional) {
        if (value == null) return null;
        return try accountInfoValueFromValue(value.?);
    }
    if (T == AccountMeta or T == *const AccountMeta or T == *AccountMeta) {
        @compileError("invoke helpers require AccountInfo or toAccountInfo()");
    }
    if (T == AccountInfo) {
        return value;
    }
    if (T == *AccountInfo or T == *const AccountInfo) {
        return value.*;
    }
    if (@hasDecl(T, "toAccountInfo")) {
        return value.toAccountInfo().*;
    }
    @compileError("invoke helpers require AccountInfo or toAccountInfo()");
}

fn validateAccess(
    info: *const AccountInfo,
    owners: ?[]const PublicKey,
    address: ?PublicKey,
    require_executable: bool,
    require_rent_exempt: bool,
    require_mut: bool,
    require_signer: bool,
) !void {
    if (owners) |allowed| {
        if (!isAllowedProgramId(allowed, info.owner_id.*)) {
            return error.ConstraintOwner;
        }
    }
    if (address) |expected_address| {
        if (!info.id.equals(expected_address)) {
            return error.ConstraintAddress;
        }
    }
    if (require_executable and info.is_executable == 0) {
        return error.ConstraintExecutable;
    }
    if (require_rent_exempt) {
        const rent = sol.rent.Rent.getOrDefault();
        if (!rent.isExempt(info.lamports.*, info.data_len)) {
            return error.ConstraintRentExempt;
        }
    }
    if (require_mut and info.is_writable == 0) {
        return error.ConstraintMut;
    }
    if (require_signer and info.is_signer == 0) {
        return error.ConstraintSigner;
    }
}

fn isAllowedProgramId(comptime ids: []const PublicKey, program_id: PublicKey) bool {
    inline for (ids) |id| {
        if (id.equals(program_id)) return true;
    }
    return false;
}

test "InterfaceProgram accepts allowed ids" {
    const allowed = [_]PublicKey{
        PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
        PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
    };
    const ProgramType = InterfaceProgram(allowed[0..]);

    var owner = PublicKey.default();
    var id = allowed[1];
    var lamports: u64 = 1;
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    _ = try ProgramType.load(&info);
}

test "InterfaceProgramAny accepts executable program" {
    var owner = PublicKey.default();
    var id = PublicKey.default();
    var lamports: u64 = 1;
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };

    _ = try InterfaceProgramAny.load(&info);
}

test "InterfaceProgramUnchecked accepts non-executable" {
    var owner = PublicKey.default();
    var id = PublicKey.default();
    var lamports: u64 = 1;
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    _ = try InterfaceProgramUnchecked.load(&info);
}

test "InterfaceAccount validates owner list" {
    const owners = [_]PublicKey{
        PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    };
    const Data = struct { value: u64 };
    const disc = discriminator_mod.accountDiscriminator("Iface");
    const Iface = InterfaceAccount(Data, .{ .discriminator = disc, .owners = owners[0..] });

    var owner = owners[0];
    var id = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 = undefined;
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &disc);
    const data_ptr: *Data = @ptrCast(@alignCast(buffer[DISCRIMINATOR_LENGTH..].ptr));
    data_ptr.* = .{ .value = 1 };

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    _ = try Iface.load(&info);
}

test "InterfaceAccountInfo validates access rules" {
    const owners = [_]PublicKey{
        PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    };
    const RawInfo = InterfaceAccountInfo(.{
        .owners = owners[0..],
        .mut = true,
        .signer = true,
    });

    var owner = owners[0];
    var id = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    _ = try RawInfo.load(&info);
}

test "InterfaceAccountInfo enforces executable" {
    const RawInfo = InterfaceAccountInfo(.{ .executable = true });

    var owner = PublicKey.default();
    var id = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    try std.testing.expectError(error.ConstraintExecutable, RawInfo.load(&info));
}

test "InterfaceAccountInfo enforces rent_exempt" {
    const RawInfo = InterfaceAccountInfo(.{ .rent_exempt = true });

    var owner = PublicKey.default();
    var id = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const rent = sol.rent.Rent.getOrDefault();
    lamports = rent.getMinimumBalance(info.data_len);
    _ = try RawInfo.load(&info);

    lamports = 0;
    try std.testing.expectError(error.ConstraintRentExempt, RawInfo.load(&info));
}

test "Interface builds CPI instruction" {
    const Accounts = struct {
        authority: *const sol.account.Account.Info,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    var key = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &key,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };
    const accounts = Accounts{ .authority = &info };

    var iface = try Interface(Program, .{}).init(allocator, PublicKey.default());
    const ix = try iface.instruction("deposit", accounts, Args{ .amount = 7 });
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
}

test "Interface builds CPI instruction with AccountMeta fields" {
    const Accounts = struct {
        authority: AccountMeta,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    const key = PublicKey.default();
    const accounts = Accounts{ .authority = AccountMeta.init(key, true, false) };

    var iface = try Interface(Program, .{}).init(allocator, PublicKey.default());
    const ix = try iface.instruction("deposit", accounts, Args{ .amount = 7 });
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].pubkey.equals(key));
    try std.testing.expect(ix.accounts[0].is_signer);
    try std.testing.expect(!ix.accounts[0].is_writable);
}

test "Interface builds CPI instruction with AccountMetaOverride" {
    const Accounts = struct {
        authority: AccountMetaOverride,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    var key = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &key,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };
    const override = AccountMetaOverride{
        .info = &info,
        .is_signer = true,
        .is_writable = true,
    };
    const accounts = Accounts{ .authority = override };

    var iface = try Interface(Program, .{}).init(allocator, PublicKey.default());
    const ix = try iface.instruction("deposit", accounts, Args{ .amount = 7 });
    defer ix.deinit(allocator);

    try std.testing.expect(ix.accounts[0].is_signer);
    try std.testing.expect(ix.accounts[0].is_writable);
}

test "Interface builds CPI instruction with remaining accounts" {
    const Accounts = struct {
        authority: *const sol.account.Account.Info,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    var key = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &key,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };
    const accounts = Accounts{ .authority = &info };

    var rem_key = PublicKey.default();
    var rem_owner = PublicKey.default();
    var rem_lamports: u64 = 1;
    const rem_info = AccountInfo{
        .id = &rem_key,
        .owner_id = &rem_owner,
        .lamports = &rem_lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };
    const remaining = [_]*const AccountInfo{ &rem_info };

    var iface = try Interface(Program, .{}).init(allocator, PublicKey.default());
    const ix = try iface.instructionWithRemaining("deposit", accounts, Args{ .amount = 7 }, remaining[0..]);
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
}

test "Interface builds CPI instruction with remaining AccountMeta" {
    const Accounts = struct {
        authority: *const sol.account.Account.Info,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    var key = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1;
    var data: [0]u8 = .{};
    const info = AccountInfo{
        .id = &key,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };
    const accounts = Accounts{ .authority = &info };

    const meta = AccountMeta.init(PublicKey.default(), false, false);
    const remaining = [_]AccountMeta{ meta };

    var iface = try Interface(Program, .{}).init(allocator, PublicKey.default());
    const ix = try iface.instructionWithRemaining("deposit", accounts, Args{ .amount = 7 }, remaining[0..]);
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), ix.accounts.len);
    try std.testing.expect(ix.accounts[1].pubkey.equals(meta.pubkey));
}

test "Interface merges duplicate metas" {
    const Accounts = struct {
        authority: AccountMeta,
        authority_dup: AccountMeta,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    const key = PublicKey.default();
    const accounts = Accounts{
        .authority = AccountMeta.init(key, false, false),
        .authority_dup = AccountMeta.init(key, true, true),
    };

    var iface = try Interface(Program, .{ .meta_merge = .merge_duplicates }).init(allocator, PublicKey.default());
    const ix = try iface.instruction("deposit", accounts, Args{ .amount = 7 });
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
    try std.testing.expect(ix.accounts[0].is_signer);
    try std.testing.expect(ix.accounts[0].is_writable);
}

test "Interface merge rejects conflicting flags" {
    const Accounts = struct {
        authority: AccountMeta,
        authority_dup: AccountMeta,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    const key = PublicKey.default();
    const accounts = Accounts{
        .authority = AccountMeta.init(key, false, false),
        .authority_dup = AccountMeta.init(key, true, true),
    };

    var iface = try Interface(Program, .{ .meta_merge = .error_on_conflict }).init(allocator, PublicKey.default());
    try std.testing.expectError(error.DuplicateAccountMeta, iface.instruction("deposit", accounts, Args{ .amount = 7 }));
}

test "Interface merge keeps same flags without error" {
    const Accounts = struct {
        authority: AccountMeta,
        authority_dup: AccountMeta,
    };
    const Args = struct { amount: u64 };

    const Program = struct {
        pub const instructions = struct {
            pub const deposit = @import("idl.zig").Instruction(.{ .Accounts = Accounts, .Args = Args });
        };
    };

    const allocator = std.testing.allocator;
    const key = PublicKey.default();
    const accounts = Accounts{
        .authority = AccountMeta.init(key, true, false),
        .authority_dup = AccountMeta.init(key, true, false),
    };

    var iface = try Interface(Program, .{ .meta_merge = .error_on_conflict }).init(allocator, PublicKey.default());
    const ix = try iface.instruction("deposit", accounts, Args{ .amount = 7 });
    defer ix.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), ix.accounts.len);
}
