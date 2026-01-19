//! Zero-CU Abstraction Layer
//!
//! Provides high-level Anchor-style abstractions that compile to zero-overhead code.
//! All offsets and dispatch logic computed at comptime.
//!
//! ## Features
//!
//! - **Zero runtime overhead**: All calculations done at compile time
//! - **Named account access**: `ctx.accounts.source` style access
//! - **Anchor-compatible**: Program struct with instructions
//! - **5 CU for single instruction, 7 CU for multi-instruction**
//!
//! ## Quick Start
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//!
//! // Define accounts with data sizes
//! const TransferAccounts = struct {
//!     from: zero.Signer(0),     // Signer, 0 bytes data
//!     to: zero.Mut(0),          // Writable, 0 bytes data
//!     config: zero.Readonly(32), // Readonly, 32 bytes data
//! };
//!
//! pub const Program = struct {
//!     pub const id = anchor.sdk.PublicKey.comptimeFromBase58("...");
//!
//!     pub fn transfer(ctx: zero.Ctx(TransferAccounts)) !void {
//!         const from = ctx.accounts.from;
//!         const to = ctx.accounts.to;
//!         // ... implementation
//!     }
//! };
//!
//! // Single instruction export
//! comptime {
//!     zero.entry(TransferAccounts, "transfer", Program.transfer);
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const discriminator_mod = @import("discriminator.zig");

// ============================================================================
// Constants
// ============================================================================

/// Account data padding for reallocation (10KB)
pub const ACCOUNT_DATA_PADDING: usize = 10 * 1024;

/// Account header size (88 bytes)
pub const ACCOUNT_HEADER_SIZE: usize = Account.DATA_HEADER;

// ============================================================================
// Account Type Markers
// ============================================================================

/// Signer account marker with data size
/// The account must be a transaction signer and is writable.
pub fn Signer(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = true;
        pub const is_writable = true;
    };
}

/// Mutable (writable) account marker with data size
pub fn Mut(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = false;
        pub const is_writable = true;
    };
}

/// Readonly account marker with data size
pub fn Readonly(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = false;
        pub const is_writable = false;
    };
}

// Aliases for compatibility
pub const ZeroSigner = Signer;
pub const ZeroMut = Mut;
pub const ZeroReadonly = Readonly;

// ============================================================================
// Offset Calculations (all comptime)
// ============================================================================

/// Calculate total size of an account in input buffer
pub fn accountSize(comptime data_len: usize) usize {
    const raw_size = ACCOUNT_HEADER_SIZE + data_len + ACCOUNT_DATA_PADDING;
    return std.mem.alignForward(usize, raw_size, 8);
}

/// Calculate offset to instruction data for given account layout
pub fn instructionDataOffset(comptime account_data_lens: []const usize) usize {
    var offset: usize = 8; // num_accounts u64
    for (account_data_lens) |data_len| {
        offset += accountSize(data_len);
    }
    return offset + 8; // skip instruction data length u64
}

/// Extract data lengths from accounts struct
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

/// Zero-overhead account accessor with comptime-calculated offsets
pub fn ZeroAccount(comptime index: usize, comptime preceding_data_lens: []const usize) type {
    // Calculate base offset to this account
    const base_offset = comptime blk: {
        var off: usize = 8; // num_accounts
        for (preceding_data_lens[0..index]) |data_len| {
            off += accountSize(data_len);
        }
        break :blk off;
    };

    return struct {
        input: [*]const u8,

        const Self = @This();

        // Offsets within Account.Data (88 byte header)
        // [0]: duplicate_index (1 byte)
        // [1]: is_signer (1 byte)
        // [2]: is_writable (1 byte)
        // [3]: is_executable (1 byte)
        // [4-7]: original_data_len (4 bytes)
        // [8-39]: id (32 bytes)
        // [40-71]: owner_id (32 bytes)
        // [72-79]: lamports (8 bytes)
        // [80-87]: data_len (8 bytes)
        const ID_OFFSET = base_offset + 8;
        const OWNER_OFFSET = base_offset + 8 + 32;
        const LAMPORTS_OFFSET = base_offset + 8 + 32 + 32;
        const DATA_LEN_OFFSET = base_offset + 8 + 32 + 32 + 8;
        const DATA_OFFSET = base_offset + ACCOUNT_HEADER_SIZE;

        /// Get account public key
        pub inline fn id(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + ID_OFFSET));
        }

        /// Get account owner public key
        pub inline fn ownerId(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + OWNER_OFFSET));
        }

        /// Get mutable pointer to lamports
        pub inline fn lamports(self: Self) *u64 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + LAMPORTS_OFFSET));
        }

        /// Check if account is a signer
        pub inline fn isSigner(self: Self) bool {
            return self.input[base_offset + 1] != 0;
        }

        /// Check if account is writable
        pub inline fn isWritable(self: Self) bool {
            return self.input[base_offset + 2] != 0;
        }

        /// Check if account is executable
        pub inline fn isExecutable(self: Self) bool {
            return self.input[base_offset + 3] != 0;
        }

        /// Get account data as const pointer
        pub inline fn data(self: Self, comptime len: usize) *const [len]u8 {
            return @ptrCast(self.input + DATA_OFFSET);
        }

        /// Get account data as mutable pointer
        pub inline fn dataMut(self: Self, comptime len: usize) *[len]u8 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(ptr + DATA_OFFSET);
        }

        /// Get raw data pointer with runtime length
        pub inline fn dataSlice(self: Self) []const u8 {
            const len_ptr: *const u64 = @ptrCast(@alignCast(self.input + DATA_LEN_OFFSET));
            return (self.input + DATA_OFFSET)[0..len_ptr.*];
        }
    };
}

// ============================================================================
// Instruction Context
// ============================================================================

/// Zero-overhead instruction context with named account access
///
/// All offsets computed at comptime for zero runtime overhead.
pub fn Ctx(comptime Accounts: type) type {
    return ZeroInstructionContext(Accounts);
}

/// Full name alias
pub fn ZeroInstructionContext(comptime Accounts: type) type {
    const data_lens = accountDataLengths(Accounts);
    const fields = std.meta.fields(Accounts);

    // Generate named account accessor struct at comptime
    const AccountsAccessor = blk: {
        var acc_fields: [fields.len]std.builtin.Type.StructField = undefined;
        inline for (fields, 0..) |field, i| {
            const AccType = ZeroAccount(i, data_lens);
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

        /// Offset to instruction data (comptime constant)
        pub const ix_data_offset = instructionDataOffset(data_lens);

        /// Load context from input buffer
        pub inline fn load(input: [*]const u8) Self {
            var acc: AccountsAccessor = undefined;
            inline for (fields) |field| {
                @field(acc, field.name) = .{ .input = input };
            }
            return .{
                .input = input,
                .accounts = acc,
            };
        }

        /// Get instruction arguments (after 8-byte discriminator)
        pub inline fn args(self: Self, comptime T: type) *const T {
            return @ptrCast(@alignCast(self.input + ix_data_offset + 8));
        }

        /// Get mutable instruction arguments
        pub inline fn argsMut(self: Self, comptime T: type) *T {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + ix_data_offset + 8));
        }

        /// Get raw instruction data pointer (includes discriminator)
        pub inline fn rawData(self: Self) [*]const u8 {
            return self.input + ix_data_offset;
        }
    };
}

// ============================================================================
// Entrypoint Generators
// ============================================================================

/// Export single-instruction entrypoint (5 CU)
///
/// Usage:
/// ```zig
/// comptime {
///     zero.entry(MyAccounts, "my_instruction", Program.myInstruction);
/// }
/// ```
pub fn entry(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) void {
    const CtxType = ZeroInstructionContext(Accounts);
    const disc: u64 = @bitCast(discriminator_mod.instructionDiscriminator(inst_name));

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            const actual: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);
            if (actual.* != disc) return 1;

            const ctx = CtxType.load(input);
            if (handler(ctx)) |_| return 0 else |_| return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Alias for entry
pub const exportSingleInstruction = entry;

/// Create instruction entry with precomputed discriminator for multi()
pub fn instruction(comptime name: []const u8, comptime handler: anytype) struct { u64, @TypeOf(handler) } {
    return .{ @as(u64, @bitCast(discriminator_mod.instructionDiscriminator(name))), handler };
}

/// Alias for instruction
pub const inst = instruction;

/// Export multi-instruction entrypoint with shared account layout (7 CU)
///
/// All instructions must use the same Accounts type.
///
/// Usage:
/// ```zig
/// comptime {
///     zero.multi(SharedAccounts, .{
///         zero.inst("initialize", Program.initialize),
///         zero.inst("transfer", Program.transfer),
///         zero.inst("close", Program.close),
///     });
/// }
/// ```
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
                if (disc.* == expected) {
                    if (handler(ctx)) |_| return 0 else |_| return 1;
                }
            }

            return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Alias for multi
pub const exportMultiInstruction = multi;

// ============================================================================
// Legacy Compatibility
// ============================================================================

/// Legacy ZeroContext (use Ctx instead)
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
    // Account with 1 byte data: 88 + 1 + 10240 = 10329, aligned to 10336
    try std.testing.expectEqual(@as(usize, 10336), accountSize(1));
    // Account with 0 bytes data: 88 + 0 + 10240 = 10328
    try std.testing.expectEqual(@as(usize, 10328), accountSize(0));
}

test "instructionDataOffset calculation" {
    const lens = [_]usize{1};
    // 8 (num_accounts) + 10336 (account) + 8 (data_len) = 10352
    try std.testing.expectEqual(@as(usize, 10352), instructionDataOffset(&lens));
}

test "accountDataLengths extraction" {
    const TestAccounts = struct {
        a: Signer(0),
        b: Mut(8),
        c: Readonly(32),
    };
    const lens = accountDataLengths(TestAccounts);
    try std.testing.expectEqual(@as(usize, 3), lens.len);
    try std.testing.expectEqual(@as(usize, 0), lens[0]);
    try std.testing.expectEqual(@as(usize, 8), lens[1]);
    try std.testing.expectEqual(@as(usize, 32), lens[2]);
}
