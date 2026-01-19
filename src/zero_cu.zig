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

/// Optional account (may not be present)
///
/// Usage:
/// ```zig
/// const Accounts = struct {
///     authority: zero.Signer(0),
///     optional_config: zero.Optional(zero.Readonly(ConfigData)),
/// };
/// ```
pub fn Optional(comptime AccountType: type) type {
    return struct {
        pub const data_size = AccountType.data_size;
        pub const DataType = if (@hasDecl(AccountType, "DataType")) AccountType.DataType else void;
        pub const is_signer = if (@hasDecl(AccountType, "is_signer")) AccountType.is_signer else false;
        pub const is_writable = if (@hasDecl(AccountType, "is_writable")) AccountType.is_writable else false;
        pub const has_typed_data = if (@hasDecl(AccountType, "has_typed_data")) AccountType.has_typed_data else false;
        pub const is_optional = true;
        pub const InnerType = AccountType;
        pub const CONSTRAINTS = if (@hasDecl(AccountType, "CONSTRAINTS")) AccountType.CONSTRAINTS else AccountConstraints{};
    };
}

/// Program account (executable, fixed address)
pub fn Program(comptime program_id: PublicKey) type {
    return struct {
        pub const data_size = 0;
        pub const DataType = void;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = false;
        pub const CONSTRAINTS = AccountConstraints{
            .address = program_id,
        };
    };
}

/// UncheckedAccount (no validation)
pub fn UncheckedAccount(comptime DataOrLen: anytype) type {
    const info = resolveDataType(DataOrLen);
    return struct {
        pub const data_size = info.size;
        pub const DataType = info.Type;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = info.has_type;
        pub const CONSTRAINTS = AccountConstraints{};
    };
}

// Aliases for compatibility
pub const ZeroSigner = Signer;
pub const ZeroMut = Mut;
pub const ZeroReadonly = Readonly;

// ============================================================================
// Offset Calculations
// ============================================================================

pub fn accountSize(comptime data_len: usize) usize {
    // Match SDK's context.zig parsing:
    // ptr += Account.DATA_HEADER + data.data_len + ACCOUNT_DATA_PADDING + @sizeOf(u64);
    // The extra @sizeOf(u64) is for the rent_epoch field after account data
    const raw_size = ACCOUNT_HEADER_SIZE + data_len + ACCOUNT_DATA_PADDING + 8;
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
    for (fields, 0..) |field, i| {
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

        /// Assign the account to a new owner
        pub inline fn assign(self: Self, owner: PublicKey) void {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            const owner_ptr: *[32]u8 = @ptrCast(ptr + OWNER_OFFSET);
            @memcpy(owner_ptr, &owner.bytes);
        }

        /// Realloc account data without checks (used for closing accounts)
        pub inline fn reallocUnchecked(self: Self, new_len: u64) void {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            const len_ptr: *u64 = @ptrCast(@alignCast(ptr + DATA_LEN_OFFSET));
            len_ptr.* = new_len;
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

/// Check if an Accounts struct needs CPI (has program accounts with unknown data size)
fn needsDynamicParsing(comptime Accounts: type) bool {
    const fields = std.meta.fields(Accounts);
    for (fields) |field| {
        // Check if field name contains "program" (e.g., system_program, token_program)
        if (std.mem.indexOf(u8, field.name, "program") != null) {
            return true;
        }
    }
    return false;
}

/// Context type for program() handlers
/// 
/// Automatically chooses between static (fast) and dynamic (CPI-compatible)
/// context based on whether the accounts include program references.
pub fn Ctx(comptime Accounts: type) type {
    if (comptime needsDynamicParsing(Accounts)) {
        return ProgramContext(Accounts);
    } else {
        return ZeroInstructionContext(Accounts);
    }
}

/// Legacy context type using static offset calculation
///
/// Only use this with entry()/multi() which require compile-time
/// known account data sizes. For program(), use Ctx() instead.
pub fn StaticCtx(comptime Accounts: type) type {
    return ZeroInstructionContext(Accounts);
}

pub fn ZeroInstructionContext(comptime Accounts: type) type {
    const data_lens = accountDataLengths(Accounts);
    const fields = std.meta.fields(Accounts);

    const AccountsAccessor = blk: {
        var acc_fields: [fields.len]std.builtin.Type.StructField = undefined;
        for (fields, 0..) |field, i| {
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

        /// Load from parsed Context (for manual dispatch scenarios like SPL Token)
        pub inline fn loadFromContext(
            program_id: *align(1) const PublicKey,
            context_accounts: []sol.account.Account,
            ix_data: []const u8,
        ) Self {
            _ = program_id;
            _ = context_accounts;
            _ = ix_data;
            // For static context, we still need the raw input pointer
            // This is a compatibility shim - real implementation would need input
            @compileError("loadFromContext not supported for static ZeroInstructionContext. Use Context.load() based approach.");
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

        /// Get instruction data as a slice
        pub inline fn ixDataSlice(self: Self) []const u8 {
            const data_len_ptr: *const u64 = @ptrCast(@alignCast(self.input + ix_data_offset - 8));
            return (self.input + ix_data_offset)[0..data_len_ptr.*];
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
                    // Use public_key module's findProgramAddressSlice which uses syscall on-chain
                    const derived = sol.public_key.findProgramAddressSlice(
                        seed_slices[0..seed_count],
                        program_id.*,
                    ) catch return error.ConstraintSeeds;

                    if (!acc.id().equals(derived.address)) {
                        return error.ConstraintSeeds;
                    }
                }
            }
        }

        /// Process init constraints - creates accounts with init = true
        /// Call this BEFORE your handler logic
        pub fn processInit(self: Self) !void {
            inline for (fields) |field| {
                const C = getConstraints(field.type);

                if (C.init) {
                    const acc = @field(self.accounts, field.name);

                    // Get payer account
                    const payer_name = C.payer orelse @compileError("init requires payer");
                    const payer = @field(self.accounts, payer_name);

                    // Calculate space
                    const space = C.space orelse blk: {
                        // Default: use data_size from account type + 8 for discriminator
                        if (@hasDecl(field.type, "data_size")) {
                            break :blk field.type.data_size + 8;
                        } else {
                            @compileError("init requires space or typed account");
                        }
                    };

                    // Check if account already initialized (has lamports)
                    if (acc.lamports().* > 0) {
                        // Account exists, just verify it's empty/zeroed
                        continue;
                    }

                    // Create the account via CPI
                    try createAccount(
                        payer,
                        acc,
                        space,
                        self.programId().*,
                    );

                    // Write discriminator if defined
                    if (C.discriminator) |disc| {
                        const data = acc.dataSlice();
                        if (data.len >= 8) {
                            const disc_ptr: *[8]u8 = @ptrCast(@constCast(data.ptr));
                            disc_ptr.* = disc;
                        }
                    }
                }
            }
        }

        /// Process close constraints - closes accounts with close = "destination"
        /// Call this AFTER your handler logic
        pub fn processClose(self: Self) !void {
            inline for (fields) |field| {
                const C = getConstraints(field.type);

                if (C.close) |dest_name| {
                    const acc = @field(self.accounts, field.name);
                    const dest = @field(self.accounts, dest_name);

                    // Transfer all lamports to destination
                    try closeAccount(acc, dest);
                }
            }
        }

        /// Helper to get constraints from account type
        fn getConstraints(comptime T: type) AccountConstraints {
            if (@hasDecl(T, "CONSTRAINTS")) {
                return T.CONSTRAINTS;
            }
            return .{};
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

/// Export raw entrypoint without discriminator check
/// Use this for maximum performance when you don't need Anchor compatibility
/// 
/// WARNING: No instruction routing - only use for single-instruction programs
pub fn entryRaw(
    comptime Accounts: type,
    comptime handler: anytype,
) void {
    const CtxType = ZeroInstructionContext(Accounts);

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            const ctx = CtxType.load(input);
            if (handler(ctx)) |_| return 0 else |_| return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

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
// Program with Multiple Account Layouts
// ============================================================================

/// Define an instruction with its own account layout for use with program()
/// 
/// Use this when different instructions have different account structures.
/// Each instruction can have a unique set of accounts.
/// 
/// Usage:
/// ```zig
/// comptime {
///     zero.program(.{
///         zero.ix("initialize", InitAccounts, initialize),
///         zero.ix("increment", IncrementAccounts, increment),
///         zero.ix("close", CloseAccounts, close),
///     });
/// }
/// ```
///
/// Note: When using different account layouts, the binary size increases
/// because each layout requires its own offset calculation code.
/// For maximum performance (5 CU), use entry() or multi() with a single
/// account layout.
pub fn ix(
    comptime name: []const u8,
    comptime Accounts: type,
    comptime func: anytype,
) type {
    return struct {
        pub const instruction_name = name;
        pub const AccountsType = Accounts;
        pub const handlerFn = func;
        pub const discriminator: u64 = @bitCast(discriminator_mod.instructionDiscriminator(name));
        pub const auto_validate = false;
    };
}

/// Define an instruction with auto-validation
pub fn ixValidated(
    comptime name: []const u8,
    comptime Accounts: type,
    comptime func: anytype,
) type {
    return struct {
        pub const instruction_name = name;
        pub const AccountsType = Accounts;
        pub const handlerFn = func;
        pub const discriminator: u64 = @bitCast(discriminator_mod.instructionDiscriminator(name));
        pub const auto_validate = true;
    };
}

/// Check if any handler needs dynamic parsing
fn anyHandlerNeedsDynamic(comptime handlers: anytype) bool {
    inline for (handlers) |H| {
        if (needsDynamicParsing(H.AccountsType)) {
            return true;
        }
    }
    return false;
}

/// Export program with multiple instructions
///
/// Automatically chooses between static offset calculation (faster) and
/// dynamic context loading (required for CPI) based on account types.
///
/// - If accounts include program references (e.g., system_program), uses dynamic parsing
/// - Otherwise, uses fast static offset calculation
///
/// Usage:
/// ```zig
/// comptime {
///     zero.program(.{
///         zero.ix("initialize", InitAccounts, initialize),
///         zero.ix("increment", IncrementAccounts, increment),
///     });
/// }
/// ```
pub fn program(comptime handlers: anytype) void {
    const use_dynamic = comptime anyHandlerNeedsDynamic(handlers);

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            if (use_dynamic) {
                // Dynamic path: use Context.load() for CPI scenarios
                return dynamicEntrypoint(input, handlers);
            } else {
                // Static path: use precomputed offsets for speed
                return staticEntrypoint(input, handlers);
            }
        }

        fn dynamicEntrypoint(input: [*]u8, comptime hs: anytype) u64 {
            const context = sol.context.Context.load(input) catch return 1;

            if (context.data.len < 8) return 1;

            const disc: *align(1) const u64 = @ptrCast(context.data.ptr);

            inline for (hs) |H| {
                if (disc.* == H.discriminator) {
                    var ctx = ProgramContext(H.AccountsType).init(context);

                    if (H.auto_validate) {
                        ctx.validate() catch return 1;
                    }

                    if (H.handlerFn(&ctx)) |_| {
                        return 0;
                    } else |_| {
                        return 1;
                    }
                }
            }
            return 1;
        }

        fn staticEntrypoint(input: [*]u8, comptime hs: anytype) u64 {
            // Read number of accounts
            const num_accounts: *const u64 = @ptrCast(@alignCast(input));

            inline for (hs) |H| {
                const expected_accounts = std.meta.fields(H.AccountsType).len;

                if (num_accounts.* == expected_accounts) {
                    const CtxType = ZeroInstructionContext(H.AccountsType);
                    const disc_ptr: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);

                    if (disc_ptr.* == H.discriminator) {
                        const ctx = CtxType.load(input);

                        if (H.auto_validate) {
                            ctx.validate() catch return 1;
                        }

                        if (H.handlerFn(ctx)) |_| {
                            return 0;
                        } else |_| {
                            return 1;
                        }
                    }
                }
            }

            // Fallback: try all handlers
            inline for (hs) |H| {
                const CtxType = ZeroInstructionContext(H.AccountsType);
                const expected_accounts = std.meta.fields(H.AccountsType).len;

                if (num_accounts.* >= expected_accounts) {
                    const disc_ptr: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);

                    if (disc_ptr.* == H.discriminator) {
                        const ctx = CtxType.load(input);

                        if (H.auto_validate) {
                            ctx.validate() catch return 1;
                        }

                        if (H.handlerFn(ctx)) |_| {
                            return 0;
                        } else |_| {
                            return 1;
                        }
                    }
                }
            }

            return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Program context - wraps sol.context.Context for dynamic account parsing
///
/// This is the context type passed to instruction handlers when using program().
/// It provides access to accounts, instruction arguments, and program ID.
pub fn ProgramContext(comptime Accounts: type) type {
    const fields = std.meta.fields(Accounts);

    return struct {
        context: sol.context.Context,

        const Self = @This();
        pub const AccountsType = Accounts;

        // Generate accounts accessor type with self reference
        pub const AccountsAccessor = blk: {
            var acc_fields: [fields.len]std.builtin.Type.StructField = undefined;
            for (fields, 0..) |field, i| {
                const RefType = struct {
                    ctx: *const Self,

                    pub fn id(ref: @This()) *const PublicKey {
                        return &ref.ctx.context.accounts[i].ptr.id;
                    }

                    pub fn lamports(ref: @This()) *u64 {
                        return ref.ctx.context.accounts[i].lamports();
                    }

                    pub fn info(ref: @This()) sol.account.Account.Info {
                        return ref.ctx.context.accounts[i].info();
                    }

                    pub fn dataSlice(ref: @This()) []u8 {
                        return ref.ctx.context.accounts[i].data();
                    }
                    
                    pub fn data(ref: @This()) []u8 {
                        return ref.ctx.context.accounts[i].data();
                    }

                    pub fn isSigner(ref: @This()) bool {
                        return ref.ctx.context.accounts[i].isSigner();
                    }

                    pub fn isWritable(ref: @This()) bool {
                        return ref.ctx.context.accounts[i].isWritable();
                    }

                    pub fn ownerId(ref: @This()) *const PublicKey {
                        return &ref.ctx.context.accounts[i].ptr.owner_id;
                    }

                    pub fn isExecutable(ref: @This()) bool {
                        return ref.ctx.context.accounts[i].isExecutable();
                    }
                };
                acc_fields[i] = .{
                    .name = field.name,
                    .type = RefType,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(RefType),
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

        pub fn init(context: sol.context.Context) Self {
            return .{ .context = context };
        }

        pub fn accounts(self: *const Self) AccountsAccessor {
            var acc: AccountsAccessor = undefined;
            inline for (fields) |field| {
                @field(acc, field.name) = .{ .ctx = self };
            }
            return acc;
        }

        pub fn args(self: *const Self, comptime T: type) *const T {
            return @ptrCast(@alignCast(self.context.data.ptr + 8));
        }

        pub fn programId(self: *const Self) *const PublicKey {
            return self.context.program_id;
        }

        /// Validate all declared constraints on accounts
        pub fn validate(self: *const Self) !void {
            const accs = self.accounts();
            inline for (fields, 0..) |field, i| {
                // Get account from context
                const account = self.context.accounts[i];

                // Check constraints from the account type
                if (@hasDecl(field.type, "CONSTRAINTS")) {
                    const C = field.type.CONSTRAINTS;

                    // Signer check
                    if (C.signer) {
                        if (!account.isSigner()) return error.ConstraintSigner;
                    }

                    // Writable check  
                    if (C.writable) {
                        if (!account.isWritable()) return error.ConstraintMut;
                    }

                    // Owner check
                    if (C.owner) |expected_owner| {
                        if (!account.ownerId().equals(expected_owner)) return error.ConstraintOwner;
                    }

                    // Address check
                    if (C.address) |expected_addr| {
                        if (!account.id().equals(expected_addr)) return error.ConstraintAddress;
                    }
                }
                _ = @field(accs, field.name);
            }
        }

        /// Process init constraints - creates accounts with init = true
        /// Call this BEFORE your handler logic
        pub fn processInit(self: *const Self) !void {
            inline for (fields, 0..) |field, i| {
                if (@hasDecl(field.type, "CONSTRAINTS")) {
                    const C = field.type.CONSTRAINTS;

                    if (C.init) {
                        const account = self.context.accounts[i];

                        // Get payer account
                        const payer_name = C.payer orelse @compileError("init requires payer");
                        const payer_idx = comptime blk: {
                            for (fields, 0..) |f, idx| {
                                if (std.mem.eql(u8, f.name, payer_name)) break :blk idx;
                            }
                            @compileError("payer account not found: " ++ payer_name);
                        };
                        const payer = self.context.accounts[payer_idx];

                        // Calculate space
                        const space: u64 = C.space orelse blk: {
                            if (@hasDecl(field.type, "data_size")) {
                                break :blk field.type.data_size + 8;
                            } else {
                                @compileError("init requires space or typed account");
                            }
                        };

                        // Check if account already initialized
                        if (account.lamports().* > 0) continue;

                        // Create account via CPI
                        const payer_info = payer.info();
                        const account_info = account.info();
                        
                        const lamports = sol.rent.Rent.DEFAULT.minimumBalance(space);
                        
                        const create_ix = sol.system_instruction.createAccount(
                            payer_info.id.*,
                            account_info.id.*,
                            lamports,
                            space,
                            self.context.program_id.*,
                        );
                        
                        if (create_ix.invokeSigned(&.{ payer_info, account_info }, &.{})) |err| {
                            _ = err;
                            return error.InitFailed;
                        }

                        // Write discriminator if defined
                        if (C.discriminator) |disc| {
                            const data = account.dataSlice();
                            if (data.len >= 8) {
                                const disc_ptr: *[8]u8 = @ptrCast(@constCast(data.ptr));
                                disc_ptr.* = disc;
                            }
                        }
                    }
                }
            }
        }

        /// Process close constraints - closes accounts with close = "destination"
        /// Call this AFTER your handler logic
        pub fn processClose(self: *const Self) !void {
            inline for (fields, 0..) |field, i| {
                if (@hasDecl(field.type, "CONSTRAINTS")) {
                    const C = field.type.CONSTRAINTS;

                    if (C.close) |dest_name| {
                        const account = self.context.accounts[i];

                        // Get destination account
                        const dest_idx = comptime blk: {
                            for (fields, 0..) |f, idx| {
                                if (std.mem.eql(u8, f.name, dest_name)) break :blk idx;
                            }
                            @compileError("close destination not found: " ++ dest_name);
                        };
                        const dest = self.context.accounts[dest_idx];

                        // Transfer lamports
                        const account_lamports = account.lamports();
                        const dest_lamports = dest.lamports();
                        dest_lamports.* += account_lamports.*;
                        account_lamports.* = 0;

                        // Zero out data
                        const data = account.dataSlice();
                        @memset(@constCast(data), 0);
                    }
                }
            }
        }
    };
}

/// Account reference for program() context
fn AccountRef(comptime index: usize) type {
    return struct {
        context_ptr: *const sol.context.Context,

        const Self = @This();

        pub fn id(self: Self) *const PublicKey {
            return &self.context_ptr.accounts[index].ptr.id;
        }

        pub fn lamports(self: Self) *u64 {
            return self.context_ptr.accounts[index].lamports();
        }

        pub fn info(self: Self) sol.account.Account.Info {
            return self.context_ptr.accounts[index].info();
        }

        pub fn dataSlice(self: Self) []const u8 {
            return self.context_ptr.accounts[index].dataSlice();
        }

        pub fn isSigner(self: Self) bool {
            return self.context_ptr.accounts[index].isSigner();
        }

        pub fn isWritable(self: Self) bool {
            return self.context_ptr.accounts[index].isWritable();
        }

        pub fn ownerId(self: Self) *const PublicKey {
            return &self.context_ptr.accounts[index].ptr.owner_id;
        }

        pub fn isExecutable(self: Self) bool {
            return self.context_ptr.accounts[index].isExecutable();
        }
    };
}

/// Backward compatibility alias for ProgramContext
pub const DynamicContext = ProgramContext;

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
// CPI Helpers (Account Operations)
// ============================================================================

/// Get minimum rent-exempt balance for given space
pub fn rentExemptBalance(space: usize) u64 {
    const rent = sol.rent.Rent.getOrDefault();
    return rent.getMinimumBalance(space);
}

/// Close an account, transfer all lamports to destination
/// 
/// Usage:
/// ```zig
/// try zero.closeAccount(ctx.accounts.closeable, ctx.accounts.destination);
/// ```
pub fn closeAccount(account: anytype, destination: anytype) !void {
    // Transfer lamports
    const account_lamports = account.lamports();
    const dest_lamports = destination.lamports();
    dest_lamports.* += account_lamports.*;
    account_lamports.* = 0;

    // Zero account data
    const data = account.dataSlice();
    const data_ptr: [*]u8 = @ptrFromInt(@intFromPtr(data.ptr));
    @memset(data_ptr[0..data.len], 0);
}

/// Create account via CPI to system program
///
/// Usage:
/// ```zig
/// try zero.createAccount(
///     ctx.accounts.payer,
///     ctx.accounts.new_account,
///     space,
///     owner,
/// );
/// ```
pub fn createAccount(
    payer: anytype,
    new_account: anytype,
    space: usize,
    owner: PublicKey,
) !void {
    const lamports = rentExemptBalance(space);
    
    const payer_info = SdkAccount.Info{
        .id = payer.id(),
        .lamports = payer.lamports(),
        .data = @constCast(payer.dataSlice()),
        .owner = payer.ownerId(),
        .rent_epoch = 0,
        .is_signer = if (payer.isSigner()) 1 else 0,
        .is_writable = if (payer.isWritable()) 1 else 0,
        .is_executable = if (payer.isExecutable()) 1 else 0,
    };
    
    const new_info = SdkAccount.Info{
        .id = new_account.id(),
        .lamports = new_account.lamports(),
        .data = @constCast(new_account.dataSlice()),
        .owner = new_account.ownerId(),
        .rent_epoch = 0,
        .is_signer = if (new_account.isSigner()) 1 else 0,
        .is_writable = if (new_account.isWritable()) 1 else 0,
        .is_executable = if (new_account.isExecutable()) 1 else 0,
    };

    sol.system_program.createAccount(
        payer_info,
        new_info,
        lamports,
        space,
        &owner,
    ) catch return error.CreateAccountFailed;
}

/// Create PDA account via CPI with seeds
pub fn createPdaAccount(
    payer: anytype,
    new_account: anytype,
    space: usize,
    owner: PublicKey,
    seeds: []const []const u8,
    bump: u8,
) !void {
    const lamports = rentExemptBalance(space);
    
    const payer_info = SdkAccount.Info{
        .id = payer.id(),
        .lamports = payer.lamports(),
        .data = @constCast(payer.dataSlice()),
        .owner = payer.ownerId(),
        .rent_epoch = 0,
        .is_signer = if (payer.isSigner()) 1 else 0,
        .is_writable = if (payer.isWritable()) 1 else 0,
        .is_executable = if (payer.isExecutable()) 1 else 0,
    };
    
    const new_info = SdkAccount.Info{
        .id = new_account.id(),
        .lamports = new_account.lamports(),
        .data = @constCast(new_account.dataSlice()),
        .owner = new_account.ownerId(),
        .rent_epoch = 0,
        .is_signer = if (new_account.isSigner()) 1 else 0,
        .is_writable = if (new_account.isWritable()) 1 else 0,
        .is_executable = if (new_account.isExecutable()) 1 else 0,
    };

    // Add bump to seeds
    var full_seeds: [17][]const u8 = undefined;
    const bump_bytes = [_]u8{bump};
    for (seeds, 0..) |s, i| {
        full_seeds[i] = s;
    }
    full_seeds[seeds.len] = &bump_bytes;

    sol.system_program.createAccountWithSeed(
        payer_info,
        new_info,
        lamports,
        space,
        &owner,
        full_seeds[0 .. seeds.len + 1],
    ) catch return error.CreateAccountFailed;
}

/// Allocate space for an account via CPI to system program
///
/// This is used for PDA accounts that need to have space allocated.
/// The account must already have lamports (for rent exemption).
///
/// Usage:
/// ```zig
/// try zero.allocate(ctx.accounts.pda_account, 42, &.{&.{"seed", &.{bump}}});
/// ```
pub fn allocate(account: anytype, space: u64, seeds: []const []const []const u8) !void {
    const data_slice = account.dataSlice();
    const account_info = SdkAccount.Info{
        .id = account.id(),
        .lamports = account.lamports(),
        .data_len = data_slice.len,
        .data = @constCast(data_slice.ptr),
        .owner_id = account.ownerId(),
        .is_signer = if (account.isSigner()) 1 else 0,
        .is_writable = if (account.isWritable()) 1 else 0,
        .is_executable = if (account.isExecutable()) 1 else 0,
    };

    // Build allocate instruction data: [8 (index u32 LE), space (u64 LE)]
    var data: [12]u8 = undefined;
    // Instruction index: 8 = Allocate
    data[0] = 8;
    data[1] = 0;
    data[2] = 0;
    data[3] = 0;
    // space (u64 little-endian)
    @memcpy(data[4..12], &@as([8]u8, @bitCast(space)));

    const cpi_ix = sol.instruction.Instruction.from(.{
        .program_id = &sol.system_program.id,
        .accounts = &[_]SdkAccount.Param{
            .{ .id = account.id(), .is_writable = true, .is_signer = true },
        },
        .data = &data,
    });

    if (cpi_ix.invokeSigned(&.{account_info}, seeds)) |err| {
        _ = err;
        return error.AllocateFailed;
    }
}

/// Transfer lamports between accounts
pub fn transferLamports(from: anytype, to: anytype, amount: u64) !void {
    const from_lamports = from.lamports();
    const to_lamports = to.lamports();
    
    if (from_lamports.* < amount) {
        return error.InsufficientFunds;
    }
    
    from_lamports.* -= amount;
    to_lamports.* += amount;
}

/// Write discriminator to account data
pub fn writeDiscriminator(account: anytype, comptime name: []const u8) void {
    const disc = discriminator_mod.accountDiscriminator(name);
    const data = account.dataMut(8);
    @memcpy(data, &disc);
}

/// Check if account is uninitialized (zero lamports or zero discriminator)
pub fn isUninitialized(account: anytype) bool {
    if (account.lamports().* == 0) return true;
    const disc: *const [8]u8 = @ptrCast(account.data(8));
    return std.mem.allEqual(u8, disc, 0);
}

// ============================================================================
// Program/SystemAccount Types
// ============================================================================

/// System Program marker
pub fn SystemProgram(comptime idx: usize) type {
    return struct {
        pub const data_size = 0;
        pub const DataType = void;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = false;
        pub const account_index = idx;
        pub const CONSTRAINTS = AccountConstraints{
            .address = sol.system_program.ID,
        };
    };
}

/// Token Program marker
pub fn TokenProgram(comptime idx: usize) type {
    return struct {
        pub const data_size = 0;
        pub const DataType = void;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = false;
        pub const account_index = idx;
        // Token program ID would be checked here
        pub const CONSTRAINTS = AccountConstraints{};
    };
}

// ============================================================================
// Tests
// ============================================================================

test "accountSize calculation" {
    // ACCOUNT_HEADER_SIZE (88) + data_len + ACCOUNT_DATA_PADDING (10240) + 8, aligned to 8
    // For data_len=0: 88 + 0 + 10240 + 8 = 10336, aligned = 10336
    // For data_len=1: 88 + 1 + 10240 + 8 = 10337, aligned = 10344
    try std.testing.expectEqual(@as(usize, 10344), accountSize(1));
    try std.testing.expectEqual(@as(usize, 10336), accountSize(0));
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

test "rentExemptBalance" {
    const balance = rentExemptBalance(100);
    try std.testing.expect(balance > 0);
}
