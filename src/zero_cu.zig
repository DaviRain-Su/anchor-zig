//! Zero-CU Abstraction Layer
//!
//! Provides high-level abstractions that compile down to zero-overhead code.
//! Uses comptime to calculate all offsets and generate optimal access patterns.

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;

/// Account data padding for reallocation
const ACCOUNT_DATA_PADDING = 10 * 1024;

/// Account header size
const ACCOUNT_HEADER_SIZE = Account.DATA_HEADER;

/// Calculate the total size of an account in the input buffer
pub fn accountSize(comptime data_len: usize) usize {
    const raw_size = ACCOUNT_HEADER_SIZE + data_len + ACCOUNT_DATA_PADDING;
    return std.mem.alignForward(usize, raw_size, 8);
}

/// Calculate offset to instruction data for given account layout
pub fn instructionDataOffset(comptime account_data_lens: []const usize) usize {
    var offset: usize = 8; // num_accounts
    for (account_data_lens) |data_len| {
        offset += accountSize(data_len);
    }
    return offset + 8; // skip data_len u64
}

/// Zero-overhead account reference
/// All offsets computed at comptime
pub fn ZeroAccount(comptime index: usize, comptime preceding_data_lens: []const usize) type {
    // Calculate offset to this account
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

        // Offsets within Account.Data
        const ID_OFFSET = base_offset + 8; // after dup/signer/writable/executable/original_data_len
        const OWNER_OFFSET = base_offset + 8 + 32;
        const LAMPORTS_OFFSET = base_offset + 8 + 32 + 32;
        const DATA_LEN_OFFSET = base_offset + 8 + 32 + 32 + 8;
        const DATA_OFFSET = base_offset + ACCOUNT_HEADER_SIZE;

        pub fn id(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + ID_OFFSET));
        }

        pub fn ownerId(self: Self) *const PublicKey {
            return @ptrCast(@alignCast(self.input + OWNER_OFFSET));
        }

        pub fn lamports(self: Self) *u64 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(@alignCast(ptr + LAMPORTS_OFFSET));
        }

        pub fn isSigner(self: Self) bool {
            return self.input[base_offset + 1] != 0;
        }

        pub fn isWritable(self: Self) bool {
            return self.input[base_offset + 2] != 0;
        }

        pub fn data(self: Self, comptime len: usize) *const [len]u8 {
            return @ptrCast(self.input + DATA_OFFSET);
        }

        pub fn dataMut(self: Self, comptime len: usize) *[len]u8 {
            const ptr: [*]u8 = @ptrFromInt(@intFromPtr(self.input));
            return @ptrCast(ptr + DATA_OFFSET);
        }
    };
}

/// Zero-overhead context for a program
/// Usage:
/// ```
/// const Ctx = ZeroContext(.{
///     .accounts = .{ 1, 8, 0 },  // data lengths for each account
/// });
/// 
/// export fn entrypoint(input: [*]u8) u64 {
///     const ctx = Ctx.load(input);
///     const acc0 = ctx.account(0);  // first account
///     const acc1 = ctx.account(1);  // second account
///     // ...
/// }
/// ```
pub fn ZeroContext(comptime config: struct {
    accounts: []const usize, // data length for each account
}) type {
    return struct {
        input: [*]const u8,

        const Self = @This();
        const account_data_lens = config.accounts;
        const num_accounts = account_data_lens.len;

        // Instruction data offset (comptime calculated)
        pub const ix_data_offset = instructionDataOffset(account_data_lens);

        pub fn load(input: [*]const u8) Self {
            return .{ .input = input };
        }

        /// Get account at comptime-known index
        pub fn account(self: Self, comptime index: usize) ZeroAccount(index, account_data_lens) {
            return .{ .input = self.input };
        }

        /// Get instruction data (after 8-byte discriminator)
        pub fn instructionData(self: Self, comptime T: type) *const T {
            return @ptrCast(@alignCast(self.input + ix_data_offset + 8));
        }

        /// Get raw instruction data pointer
        pub fn rawInstructionData(self: Self) [*]const u8 {
            return self.input + ix_data_offset;
        }

        /// Check discriminator (zero-cost u64 compare)
        pub fn checkDiscriminator(self: Self, comptime expected: [8]u8) bool {
            const expected_u64: u64 = @bitCast(expected);
            const actual: *align(1) const u64 = @ptrCast(self.input + ix_data_offset);
            return actual.* == expected_u64;
        }
    };
}

/// Generate a zero-overhead program from type definitions
/// 
/// Usage:
/// ```
/// const MyAccounts = struct {
///     source: ZeroSigner(8),      // 8 bytes data
///     dest: ZeroMut(0),           // 0 bytes data  
///     config: ZeroReadonly(32),   // 32 bytes data
/// };
/// 
/// const Program = ZeroProgram(MyAccounts, .{
///     .check = checkHandler,
///     .transfer = transferHandler,
/// });
/// ```
pub fn ZeroSigner(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = true;
        pub const is_writable = true;
    };
}

pub fn ZeroMut(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = false;
        pub const is_writable = true;
    };
}

pub fn ZeroReadonly(comptime data_len: usize) type {
    return struct {
        pub const data_size = data_len;
        pub const is_signer = false;
        pub const is_writable = false;
    };
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

/// Create a zero-overhead program dispatcher
pub fn ZeroDispatch(
    comptime Accounts: type,
    comptime instructions: anytype,
) type {
    const data_lens = accountDataLengths(Accounts);
    const Ctx = ZeroContext(.{ .accounts = data_lens });

    return struct {
        pub fn process(input: [*]u8) u64 {
            const ctx = Ctx.load(input);

            // Try each instruction's discriminator
            inline for (std.meta.fields(@TypeOf(instructions))) |field| {
                const disc = @import("discriminator.zig").instructionDiscriminator(field.name);
                if (ctx.checkDiscriminator(disc)) {
                    const handler = @field(instructions, field.name);
                    return handler(ctx);
                }
            }

            return 1; // Unknown instruction
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

test "accountSize calculation" {
    // Account with 1 byte data
    // Header(88) + Data(1) + Padding(10240) = 10329, aligned to 10336
    try std.testing.expectEqual(@as(usize, 10336), accountSize(1));

    // Account with 0 bytes data
    try std.testing.expectEqual(@as(usize, 10328), accountSize(0));
}

test "instructionDataOffset calculation" {
    // Single account with 1 byte data
    const lens1 = [_]usize{1};
    // 8 (num_accounts) + 10336 (account) + 8 (data_len) = 10352
    try std.testing.expectEqual(@as(usize, 10352), instructionDataOffset(&lens1));
}
