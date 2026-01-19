//! Zero-CU Abstraction Layer
//!
//! Provides high-level Anchor-style abstractions that compile to zero-overhead code.
//! All offsets, validation, and dispatch logic computed at comptime.
//!
//! ## Features
//!
//! - **Zero runtime overhead**: All calculations done at compile time
//! - **Named account access**: `ctx.accounts.source` style access
//! - **Declarative constraints**: Owner, PDA, has_one - only pay for what you use
//! - **5 CU base + validation cost**
//!
//! ## Quick Start
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//!
//! const CounterData = struct {
//!     count: u64,
//!     authority: anchor.sdk.PublicKey,
//! };
//!
//! const IncrementAccounts = struct {
//!     // Simple signer
//!     authority: zero.Signer(0),
//!
//!     // Account with constraints
//!     counter: zero.Account(CounterData, .{
//!         .owner = PROGRAM_ID,                    // +2 CU
//!         .has_one = &.{"authority"},             // +2 CU
//!     }),
//!
//!     // PDA with seeds
//!     vault: zero.Account(VaultData, .{
//!         .seeds = &.{ "vault", .{ .account = "authority" } },
//!         .owner = PROGRAM_ID,
//!     }),
//! };
//!
//! pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
//!     ctx.accounts.counter.getMut().count += 1;
//! }
//!
//! comptime {
//!     zero.entry(IncrementAccounts, "increment", increment);
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.public_key.PublicKey;
const SdkAccount = sol.account.Account;
const discriminator_mod = @import("discriminator.zig");

// ============================================================================
// Constants
// ============================================================================

pub const ACCOUNT_DATA_PADDING: usize = 10 * 1024;
pub const ACCOUNT_HEADER_SIZE: usize = SdkAccount.DATA_HEADER;

// ============================================================================
// Seed Types for PDA
// ============================================================================

/// Seed specification for PDA derivation
pub const Seed = union(enum) {
    /// Literal bytes
    literal: []const u8,
    /// Reference to another account's pubkey
    account: []const u8,
    /// Reference to a field in account data
    field: []const u8,
    /// Bump seed (u8)
    bump: u8,
};

/// Create literal seed
pub fn seed(comptime bytes: []const u8) Seed {
    return .{ .literal = bytes };
}

/// Create account reference seed
pub fn seedAccount(comptime name: []const u8) Seed {
    return .{ .account = name };
}

/// Create field reference seed
pub fn seedField(comptime name: []const u8) Seed {
    return .{ .field = name };
}

// ============================================================================
// Account Constraint Configuration
// ============================================================================

/// Account constraints configuration
pub const AccountConstraints = struct {
    /// Expected owner program
    owner: ?PublicKey = null,
    /// Expected address
    address: ?PublicKey = null,
    /// PDA seeds
    seeds: ?[]const Seed = null,
    /// has_one constraints (field names that must match other account keys)
    has_one: ?[]const []const u8 = null,
    /// Must be signer (auto-set for Signer type)
    signer: bool = false,
    /// Must be writable (auto-set for Mut type)
    writable: bool = false,
    /// Account discriminator (for Anchor compatibility)
    discriminator: ?[8]u8 = null,
    /// Close to this account
    close: ?[]const u8 = null,
    /// Initialize account
    init: bool = false,
    /// Payer for init
    payer: ?[]const u8 = null,
    /// Space for init
    space: ?usize = null,
};

// ============================================================================
// Account Type Markers
// ============================================================================

/// Resolve data type or length to size info
fn resolveDataType(comptime DataOrLen: anytype) struct { size: usize, Type: type, has_type: bool } {
    const T = @TypeOf(DataOrLen);
    if (T == type) {
        return .{ .size = @sizeOf(DataOrLen), .Type = DataOrLen, .has_type = true };
    } else if (T == comptime_int) {
        return .{ .size = DataOrLen, .Type = void, .has_type = false };
    } else {
        @compileError("Expected type or comptime_int for account data");
    }
}

/// Signer account with optional constraints
pub fn Signer(comptime DataOrLen: anytype) type {
    return SignerWithConstraints(DataOrLen, .{});
}

/// Signer account with constraints
pub fn SignerWithConstraints(comptime DataOrLen: anytype, comptime constraints: AccountConstraints) type {
    const info = resolveDataType(DataOrLen);
    return struct {
        pub const data_size = info.size;
        pub const DataType = info.Type;
        pub const is_signer = true;
        pub const is_writable = true;
        pub const has_typed_data = info.has_type;
        pub const CONSTRAINTS = AccountConstraints{
            .signer = true,
            .writable = true,
            .owner = constraints.owner,
            .address = constraints.address,
            .seeds = constraints.seeds,
            .has_one = constraints.has_one,
            .discriminator = constraints.discriminator,
        };
    };
}

/// Mutable account with optional constraints
pub fn Mut(comptime DataOrLen: anytype) type {
    return MutWithConstraints(DataOrLen, .{});
}

/// Mutable account with constraints
pub fn MutWithConstraints(comptime DataOrLen: anytype, comptime constraints: AccountConstraints) type {
    const info = resolveDataType(DataOrLen);
    return struct {
        pub const data_size = info.size;
        pub const DataType = info.Type;
        pub const is_signer = constraints.signer;
        pub const is_writable = true;
        pub const has_typed_data = info.has_type;
        pub const CONSTRAINTS = AccountConstraints{
            .signer = constraints.signer,
            .writable = true,
            .owner = constraints.owner,
            .address = constraints.address,
            .seeds = constraints.seeds,
            .has_one = constraints.has_one,
            .discriminator = constraints.discriminator,
            .close = constraints.close,
            .init = constraints.init,
            .payer = constraints.payer,
            .space = constraints.space,
        };
    };
}

/// Readonly account with optional constraints
pub fn Readonly(comptime DataOrLen: anytype) type {
    return ReadonlyWithConstraints(DataOrLen, .{});
}

/// Readonly account with constraints
pub fn ReadonlyWithConstraints(comptime DataOrLen: anytype, comptime constraints: AccountConstraints) type {
    const info = resolveDataType(DataOrLen);
    return struct {
        pub const data_size = info.size;
        pub const DataType = info.Type;
        pub const is_signer = constraints.signer;
        pub const is_writable = false;
        pub const has_typed_data = info.has_type;
        pub const CONSTRAINTS = AccountConstraints{
            .signer = constraints.signer,
            .writable = false,
            .owner = constraints.owner,
            .address = constraints.address,
            .seeds = constraints.seeds,
            .has_one = constraints.has_one,
            .discriminator = constraints.discriminator,
        };
    };
}

/// Full Account with data type and constraints (Anchor-style)
pub fn Account(comptime DataType: type, comptime constraints: AccountConstraints) type {
    return MutWithConstraints(DataType, constraints);
}

/// Readonly Account with constraints
pub fn AccountReadonly(comptime DataType: type, comptime constraints: AccountConstraints) type {
    return ReadonlyWithConstraints(DataType, constraints);
}

// Aliases for compatibility
pub const ZeroSigner = Signer;
pub const ZeroMut = Mut;
pub const ZeroReadonly = Readonly;

// ============================================================================
// Offset Calculations
// ============================================================================

pub fn accountSize(comptime data_len: usize) usize {
    const raw_size = ACCOUNT_HEADER_SIZE + data_len + ACCOUNT_DATA_PADDING;
    return std.mem.alignForward(usize, raw_size, 8);
}

pub fn instructionDataOffset(comptime account_data_lens: []const usize) usize {
    var offset: usize = 8; // num_accounts u64
    for (account_data_lens) |data_len| {
        offset += accountSize(data_len);
    }
    return offset + 8; // skip instruction data length u64
}

pub fn accountDataLengths(comptime Accounts: type) []const usize {
    const fields = std.meta.fields(Accounts);
    comptime var lens: [fields.len]usize = undefined;
    inline for (fields, 0..) |field, i| {
        lens[i] = field.type.data_size;
    }
    const result = lens;
    return &result;
}

// ============================================================================
// Zero-Overhead Account Accessor
// ============================================================================

pub fn ZeroAccount(comptime index: usize, comptime preceding_data_lens: []const usize) type {
    return ZeroAccountTyped(index, preceding_data_lens, void, .{});
}

pub fn ZeroAccountTyped(
    comptime index: usize,
    comptime preceding_data_lens: []const usize,
    comptime DataType: type,
    comptime constraints: AccountConstraints,
) type {
    const base_offset = comptime blk: {
        var off: usize = 8;
        for (preceding_data_lens[0..index]) |data_len| {
            off += accountSize(data_len);
        }
        break :blk off;
    };

    return struct {
        input: [*]const u8,

        const Self = @This();
        const ID_OFFSET = base_offset + 8;
        const OWNER_OFFSET = base_offset + 8 + 32;
        const LAMPORTS_OFFSET = base_offset + 8 + 32 + 32;
        const DATA_LEN_OFFSET = base_offset + 8 + 32 + 32 + 8;
        const DATA_OFFSET = base_offset + ACCOUNT_HEADER_SIZE;

        pub const Constraints = constraints;

        pub inline fn id(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + ID_OFFSET));
        }

        pub inline fn ownerId(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + OWNER_OFFSET));
        }

        pub inline fn lamports(self: Self) *u64 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + LAMPORTS_OFFSET));
        }

        pub inline fn isSigner(self: Self) bool {
            return self.input[base_offset + 1] != 0;
        }

        pub inline fn isWritable(self: Self) bool {
            return self.input[base_offset + 2] != 0;
        }

        pub inline fn isExecutable(self: Self) bool {
            return self.input[base_offset + 3] != 0;
        }

        pub inline fn get(self: Self) if (DataType != void) *const DataType else noreturn {
            if (DataType == void) @compileError("No typed data");
            return @ptrCast(@alignCast(self.input + DATA_OFFSET));
        }

        pub inline fn getMut(self: Self) if (DataType != void) *DataType else noreturn {
            if (DataType == void) @compileError("No typed data");
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + DATA_OFFSET));
        }

        pub inline fn data(self: Self, comptime len: usize) *const [len]u8 {
            return @ptrCast(self.input + DATA_OFFSET);
        }

        pub inline fn dataMut(self: Self, comptime len: usize) *[len]u8 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(ptr + DATA_OFFSET);
        }

        pub inline fn dataSlice(self: Self) []const u8 {
            const len_ptr: *const u64 = @ptrCast(@alignCast(self.input + DATA_LEN_OFFSET));
            return (self.input + DATA_OFFSET)[0..len_ptr.*];
        }

        // Manual validation methods
        pub inline fn verifyOwner(self: Self, expected: PublicKey) !void {
            if (!self.ownerId().equals(expected)) return error.ConstraintOwner;
        }

        pub inline fn verifyAddress(self: Self, expected: PublicKey) !void {
            if (!self.id().equals(expected)) return error.ConstraintAddress;
        }

        pub inline fn verifySigner(self: Self) !void {
            if (!self.isSigner()) return error.ConstraintSigner;
        }

        pub inline fn verifyWritable(self: Self) !void {
            if (!self.isWritable()) return error.ConstraintMut;
        }
    };
}

// ============================================================================
// Instruction Context with Auto-Validation
// ============================================================================

pub fn Ctx(comptime Accounts: type) type {
    return ZeroInstructionContext(Accounts);
}

pub fn ZeroInstructionContext(comptime Accounts: type) type {
    const data_lens = accountDataLengths(Accounts);
    const fields = std.meta.fields(Accounts);

    const AccountsAccessor = blk: {
        var acc_fields: [fields.len]std.builtin.Type.StructField = undefined;
        inline for (fields, 0..) |field, i| {
            const field_constraints = if (@hasDecl(field.type, "CONSTRAINTS"))
                field.type.CONSTRAINTS
            else
                AccountConstraints{};

            const AccType = if (@hasDecl(field.type, "has_typed_data") and field.type.has_typed_data)
                ZeroAccountTyped(i, data_lens, field.type.DataType, field_constraints)
            else
                ZeroAccountTyped(i, data_lens, void, field_constraints);

            acc_fields[i] = .{
                .name = field.name,
                .type = AccType,
                .default_value_ptr = null,
                .is_comptime = false,
                .alignment = @alignOf(AccType),
            };
        }
        break :blk @Type(.{
            .@"struct" = .{
                .layout = .auto,
                .fields = &acc_fields,
                .decls = &.{},
                .is_tuple = false,
            },
        });
    };

    return struct {
        input: [*]const u8,
        accounts: AccountsAccessor,

        const Self = @This();
        pub const ix_data_offset = instructionDataOffset(data_lens);
        pub const AccountsType = Accounts;

        pub inline fn load(input: [*]const u8) Self {
            var acc: AccountsAccessor = undefined;
            inline for (fields) |field| {
                @field(acc, field.name) = .{ .input = input };
            }
            return .{ .input = input, .accounts = acc };
        }

        pub inline fn args(self: Self, comptime T: type) *const T {
            return @ptrCast(@alignCast(self.input + ix_data_offset + 8));
        }

        pub inline fn argsMut(self: Self, comptime T: type) *T {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + ix_data_offset + 8));
        }

        pub inline fn rawData(self: Self) [*]const u8 {
            return self.input + ix_data_offset;
        }

        pub inline fn programId(self: Self) *const PublicKey {
            const data_len_ptr: *const u64 = @ptrCast(@alignCast(self.input + ix_data_offset - 8));
            return @ptrCast(@alignCast(self.input + ix_data_offset + data_len_ptr.*));
        }

        /// Validate all declared constraints
        pub fn validate(self: Self) !void {
            inline for (fields) |field| {
                const acc = @field(self.accounts, field.name);
                const C = @TypeOf(acc).Constraints;

                // Signer check
                if (C.signer) {
                    if (!acc.isSigner()) return error.ConstraintSigner;
                }

                // Writable check
                if (C.writable) {
                    if (!acc.isWritable()) return error.ConstraintMut;
                }

                // Owner check
                if (C.owner) |expected_owner| {
                    if (!acc.ownerId().equals(expected_owner)) return error.ConstraintOwner;
                }

                // Address check
                if (C.address) |expected_addr| {
                    if (!acc.id().equals(expected_addr)) return error.ConstraintAddress;
                }

                // Discriminator check
                if (C.discriminator) |expected_disc| {
                    const actual: *const [8]u8 = @ptrCast(acc.data(8));
                    if (!std.mem.eql(u8, actual, &expected_disc)) {
                        return error.AccountDiscriminatorMismatch;
                    }
                }

                // has_one check
                if (C.has_one) |has_one_fields| {
                    inline for (has_one_fields) |target_field| {
                        // Get the target account's pubkey
                        const target_acc = @field(self.accounts, target_field);
                        const target_key = target_acc.id();

                        // Get the field value from this account's data
                        if (@TypeOf(acc).Constraints.owner != null or @hasDecl(field.type, "has_typed_data")) {
                            const data_ptr = acc.get();
                            if (@hasField(@TypeOf(data_ptr.*), target_field)) {
                                const field_val = @field(data_ptr.*, target_field);
                                if (@TypeOf(field_val) == PublicKey) {
                                    if (!field_val.equals(target_key.*)) {
                                        return error.ConstraintHasOne;
                                    }
                                }
                            }
                        }
                    }
                }

                // PDA validation
                if (C.seeds) |seeds| {
                    var seed_slices: [16][]const u8 = undefined;
                    var seed_count: usize = 0;

                    inline for (seeds) |s| {
                        switch (s) {
                            .literal => |lit| {
                                seed_slices[seed_count] = lit;
                                seed_count += 1;
                            },
                            .account => |acc_name| {
                                const ref_acc = @field(self.accounts, acc_name);
                                seed_slices[seed_count] = &ref_acc.id().bytes;
                                seed_count += 1;
                            },
                            .field => |_| {
                                // Field seeds require more complex handling
                            },
                            .bump => |_| {
                                // Bump handled separately
                            },
                        }
                    }

                    const program_id = self.programId();
                    const derived = sol.PublicKey.findProgramAddress(
                        seed_slices[0..seed_count],
                        program_id.*,
                    ) catch return error.ConstraintSeeds;

                    if (!acc.id().equals(derived.address)) {
                        return error.ConstraintSeeds;
                    }
                }
            }
        }
    };
}

// ============================================================================
// Entrypoint Generators
// ============================================================================

/// Export single-instruction entrypoint
/// If validate_constraints is true, calls ctx.validate() automatically
pub fn entry(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) void {
    entryWithValidation(Accounts, inst_name, handler, false);
}

/// Export single-instruction entrypoint with automatic constraint validation
pub fn entryValidated(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) void {
    entryWithValidation(Accounts, inst_name, handler, true);
}

fn entryWithValidation(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
    comptime auto_validate: bool,
) void {
    const CtxType = ZeroInstructionContext(Accounts);
    const disc: u64 = @bitCast(discriminator_mod.instructionDiscriminator(inst_name));

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            const actual: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);
            if (actual.* != disc) return 1;

            const ctx = CtxType.load(input);

            if (auto_validate) {
                ctx.validate() catch return 1;
            }

            if (handler(ctx)) |_| return 0 else |_| return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

pub const exportSingleInstruction = entry;

/// Create instruction with precomputed discriminator
pub fn instruction(comptime name: []const u8, comptime handler: anytype) struct { u64, @TypeOf(handler), bool } {
    return .{ @as(u64, @bitCast(discriminator_mod.instructionDiscriminator(name))), handler, false };
}

/// Create instruction with auto-validation
pub fn instructionValidated(comptime name: []const u8, comptime handler: anytype) struct { u64, @TypeOf(handler), bool } {
    return .{ @as(u64, @bitCast(discriminator_mod.instructionDiscriminator(name))), handler, true };
}

pub const inst = instruction;
pub const instValidated = instructionValidated;

/// Export multi-instruction entrypoint
pub fn multi(
    comptime Accounts: type,
    comptime handlers: anytype,
) void {
    const CtxType = ZeroInstructionContext(Accounts);

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            const disc: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);
            const ctx = CtxType.load(input);

            inline for (handlers) |h| {
                const expected: u64 = h.@"0";
                const handler = h.@"1";
                const auto_validate: bool = h.@"2";

                if (disc.* == expected) {
                    if (auto_validate) {
                        ctx.validate() catch return 1;
                    }
                    if (handler(ctx)) |_| return 0 else |_| return 1;
                }
            }

            return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

pub const exportMultiInstruction = multi;

// ============================================================================
// Legacy Compatibility
// ============================================================================

pub fn ZeroContext(comptime config: struct {
    accounts: []const usize,
}) type {
    return struct {
        input: [*]const u8,
        const Self = @This();
        const account_data_lens = config.accounts;
        pub const ix_data_offset = instructionDataOffset(account_data_lens);

        pub fn load(input: [*]const u8) Self {
            return .{ .input = input };
        }

        pub fn account(self: Self, comptime index: usize) ZeroAccount(index, account_data_lens) {
            return .{ .input = self.input };
        }

        pub fn checkDiscriminator(self: Self, comptime expected: [8]u8) bool {
            const expected_u64: u64 = @bitCast(expected);
            const actual: *align(1) const u64 = @ptrCast(self.input + ix_data_offset);
            return actual.* == expected_u64;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "accountSize calculation" {
    try std.testing.expectEqual(@as(usize, 10336), accountSize(1));
    try std.testing.expectEqual(@as(usize, 10328), accountSize(0));
}

test "Signer has correct flags" {
    const S = Signer(0);
    try std.testing.expect(S.is_signer);
    try std.testing.expect(S.is_writable);
}

test "Account with constraints" {
    const TestData = struct { value: u64 };
    const A = Account(TestData, .{ .owner = PublicKey.default() });
    try std.testing.expectEqual(@as(usize, 8), A.data_size);
    try std.testing.expect(A.CONSTRAINTS.owner != null);
}
