//! Zig implementation of Anchor Program account type
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/program.rs
//!
//! Program represents a reference to an executable program account.
//! It validates that the account is executable and matches the expected
//! program ID.
//!
//! ## Example
//! ```zig
//! const MyAccounts = struct {
//!     system_program: anchor.Program(system_program.ID),
//!     token_program: anchor.Program(token.TOKEN_PROGRAM_ID),
//! };
//! ```

const std = @import("std");
const anchor_error = @import("error.zig");
const attr_mod = @import("attr.zig");
const sol = @import("solana_program_sdk");

// Import from parent SDK
const sdk_account = sol.account;
const PublicKey = sol.PublicKey;

const AnchorError = anchor_error.AnchorError;
const AccountInfo = sdk_account.Account.Info;
const Attr = attr_mod.Attr;

/// Program account type with expected ID
///
/// Validates that an account is an executable program with the expected ID.
///
/// Type Parameters:
/// - `expected_id`: The expected program ID
///
/// Anchor equivalent: `Program<'info, T>`
///
/// Example:
/// ```zig
/// const SystemProgram = anchor.Program(system_program.ID);
/// ```
pub fn Program(comptime expected_id: PublicKey) type {
    return struct {
        const Self = @This();

        /// Expected program ID (compile-time constant)
        pub const ID: PublicKey = expected_id;

        /// The account info
        info: *const AccountInfo,

        /// Load and validate a program account
        ///
        /// Validates:
        /// - Account is executable
        /// - Account ID matches expected program ID
        pub fn load(info: *const AccountInfo) !Self {
            // Must be executable
            if (info.is_executable == 0) {
                return error.ConstraintExecutable;
            }

            // Must match expected program ID
            if (!info.id.equals(expected_id)) {
                return error.InvalidProgramId;
            }

            return Self{ .info = info };
        }

        /// Get the program ID
        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        /// Get the underlying account info
        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Unchecked program reference
///
/// Validates that an account is executable but does not check the program ID.
/// Use with caution - prefer `Program(id)` when possible.
///
/// Anchor equivalent: `UncheckedAccount` with executable check
pub const UncheckedProgram = struct {
    /// The account info
    info: *const AccountInfo,

    /// Load and validate an executable account
    pub fn load(info: *const AccountInfo) !UncheckedProgram {
        if (info.is_executable == 0) {
            return error.ConstraintExecutable;
        }
        return UncheckedProgram{ .info = info };
    }

    /// Get the program ID
    pub fn key(self: UncheckedProgram) *const PublicKey {
        return self.info.id;
    }

    /// Get the underlying account info
    pub fn toAccountInfo(self: UncheckedProgram) *const AccountInfo {
        return self.info;
    }
};

/// Program field wrapper with additional typed attrs.
pub fn ProgramField(comptime Base: type, comptime attrs: []const Attr) type {
    comptime var address: ?PublicKey = null;
    comptime var owner: ?PublicKey = null;
    comptime var executable = false;

    inline for (attrs) |attr| {
        switch (attr) {
            .address => |value| {
                if (address != null) @compileError("address already set");
                address = value;
            },
            .owner => |value| {
                if (owner != null) @compileError("owner already set");
                owner = value;
            },
            .executable => executable = true,
            else => @compileError("Program fields only support address/owner/executable attrs"),
        }
    }

    if (@hasDecl(Base, "ID")) {
        if (address) |value| {
            if (!std.mem.eql(u8, &Base.ID.bytes, &value.bytes)) {
                @compileError("Program address must match Program.ID");
            }
        }
    }

    return struct {
        const Self = @This();

        base: Base,

        pub fn load(info: *const AccountInfo) !Self {
            const base = try Base.load(info);
            if (executable and info.is_executable == 0) {
                return error.ConstraintExecutable;
            }
            if (address) |value| {
                if (!info.id.equals(value)) {
                    return error.ConstraintAddress;
                }
            }
            if (owner) |value| {
                if (!info.owner_id.equals(value)) {
                    return error.ConstraintOwner;
                }
            }
            return .{ .base = base };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.base.key();
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.base.toAccountInfo();
        }
    };
}

/// Program validation errors
pub const ProgramError = error{
    ConstraintExecutable,
    InvalidProgramId,
};

// ============================================================================
// Tests
// ============================================================================

test "Program.load accepts matching executable" {
    const expected_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const SystemProgram = Program(expected_id);

    var id = expected_id;
    var owner = PublicKey.default();
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
    };

    const program = try SystemProgram.load(&info);
    try std.testing.expect(program.key().equals(expected_id));
}

test "Program.load rejects non-executable" {
    const expected_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const SystemProgram = Program(expected_id);

    var id = expected_id;
    var owner = PublicKey.default();
    var lamports: u64 = 1;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0, // Not executable
    };

    try std.testing.expectError(error.ConstraintExecutable, SystemProgram.load(&info));
}

test "Program.load rejects wrong program ID" {
    // Use Token Program ID as expected - different from default
    const expected_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const TokenProgram = Program(expected_id);

    var wrong_id = PublicKey.default(); // Different from expected_id (Token Program)
    var owner = PublicKey.default();
    var lamports: u64 = 1;

    const info = AccountInfo{
        .id = &wrong_id, // Wrong ID
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    try std.testing.expectError(error.InvalidProgramId, TokenProgram.load(&info));
}

test "UncheckedProgram.load accepts any executable" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
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
    };

    const program = try UncheckedProgram.load(&info);
    try std.testing.expectEqual(&id, program.key());
}

test "UncheckedProgram.load rejects non-executable" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
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
    };

    try std.testing.expectError(error.ConstraintExecutable, UncheckedProgram.load(&info));
}

test "Program.ID is accessible at comptime" {
    const expected_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    const SystemProgram = Program(expected_id);

    // ID should be accessible at comptime
    comptime {
        std.debug.assert(SystemProgram.ID.equals(expected_id));
    }
}
