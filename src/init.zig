//! Zig implementation of Anchor account initialization
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/init.rs
//!
//! Account initialization utilities for creating new accounts, including
//! PDA accounts via Cross-Program Invocation (CPI).
//!
//! ## Example
//! ```zig
//! // Create a new account at a PDA
//! try init.createAccountAtPda(
//!     payer_info,
//!     new_account_info,
//!     &program_id,
//!     Counter.SPACE,
//!     &.{ "counter", &authority.bytes },
//!     bump,
//!     &program_id,
//! );
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const system_program = sol.system_program;
const instruction_mod = sol.instruction;
const rent_mod = sol.rent;
const public_key_mod = sol.public_key;
const sdk_account = sol.account;

const PublicKey = sol.PublicKey;
const AccountInfo = sdk_account.Account.Info;
const Instruction = instruction_mod.Instruction;
const Rent = rent_mod.Rent;

/// Account initialization errors
pub const InitError = error{
    /// Payer account has insufficient lamports
    InsufficientLamports,
    /// Failed to invoke system program
    InvokeFailed,
    /// Account already initialized
    AccountAlreadyInitialized,
    /// Invalid space parameter
    InvalidSpace,
    /// Payer must be a signer
    PayerNotSigner,
    /// New account must be writable
    AccountNotWritable,
    /// Failed to get rent sysvar
    RentUnavailable,
    /// Seeds derivation failed
    SeedsDerivationFailed,
};

/// Configuration for account initialization
pub const InitConfig = struct {
    /// Required space for the account data
    space: usize,

    /// Field name of the payer account in the Accounts struct
    payer: []const u8,

    /// Owner program for the new account
    owner: PublicKey,
};

/// Configuration for batch account initialization.
pub const BatchInitConfig = struct {
    payer: *const AccountInfo,
    new_account: *const AccountInfo,
    owner: *const PublicKey,
    space: usize,
    system_program: *const AccountInfo,
};

/// Get the minimum rent-exempt balance for an account
///
/// Returns the minimum lamports needed for an account with the given
/// data size to be rent-exempt.
///
/// Example:
/// ```zig
/// const balance = try rentExemptBalance(Counter.SPACE);
/// ```
pub fn rentExemptBalance(space: usize) !u64 {
    const rent = Rent.getOrDefault();
    return rent.getMinimumBalance(space);
}

/// Calculate rent-exempt balance using default rent values
///
/// Uses Solana's default rent parameters when syscall is unavailable.
/// This is useful for off-chain testing.
pub fn rentExemptBalanceDefault(space: usize) u64 {
    const total_size: u64 = Rent.account_storage_overhead + space;
    return total_size * Rent.default_lamports_per_byte_year * @as(u64, @intFromFloat(Rent.default_exemption_threshold));
}

/// Create a new account via CPI to system program
///
/// Creates a regular (non-PDA) account owned by the specified program.
///
/// Parameters:
/// - payer: Account info of the payer (must be signer)
/// - new_account: Account info of the new account (must be signer and writable)
/// - owner: Program that will own the new account
/// - space: Size of the account data
/// - system_program: System program account info
///
/// Example:
/// ```zig
/// try createAccount(
///     payer_info,
///     new_account_info,
///     &my_program_id,
///     Counter.SPACE,
///     system_program_info,
/// );
/// ```
pub fn createAccount(
    payer: *const AccountInfo,
    new_account: *const AccountInfo,
    owner: *const PublicKey,
    space: usize,
    system_program_info: *const AccountInfo,
) InitError!void {
    // Validate payer is signer
    if (payer.is_signer == 0) {
        return InitError.PayerNotSigner;
    }

    // Validate new account is writable
    if (new_account.is_writable == 0) {
        return InitError.AccountNotWritable;
    }

    // Calculate rent-exempt balance
    const lamports = rentExemptBalance(space) catch {
        return InitError.RentUnavailable;
    };

    // Build the create account instruction
    const ix = Instruction.from(.{
        .program_id = &system_program.id,
        .accounts = &[_]sdk_account.Account.Param{
            .{
                .id = payer.id,
                .is_signer = true,
                .is_writable = true,
            },
            .{
                .id = new_account.id,
                .is_signer = true,
                .is_writable = true,
            },
        },
        .data = &buildCreateAccountData(lamports, space, owner),
    });

    // Invoke the system program
    const result = ix.invoke(&[_]AccountInfo{ payer.*, new_account.*, system_program_info.* });
    if (result != null) {
        return InitError.InvokeFailed;
    }
}

/// Create multiple accounts via CPI to the system program.
///
/// This is a convenience wrapper around `createAccount` for batch setup.
/// Each entry is processed sequentially; the first failure aborts the batch.
pub fn createAccounts(configs: []const BatchInitConfig) InitError!void {
    for (configs) |cfg| {
        try createAccount(
            cfg.payer,
            cfg.new_account,
            cfg.owner,
            cfg.space,
            cfg.system_program,
        );
    }
}

/// Create a new account at a PDA via CPI to system program
///
/// Creates an account at a Program Derived Address. The PDA signer seeds
/// are used to sign the CPI on behalf of the PDA.
///
/// Parameters:
/// - payer: Account info of the payer (must be signer)
/// - new_account: Account info of the new account (must be writable, PDA address)
/// - owner: Program that will own the new account
/// - space: Size of the account data
/// - seeds: Seeds used to derive the PDA (without bump)
/// - bump: Bump seed for the PDA
/// - program_id: Program ID used to derive the PDA (for signing)
/// - system_program: System program account info
///
/// Example:
/// ```zig
/// try createAccountAtPda(
///     payer_info,
///     counter_info,
///     &my_program_id,
///     Counter.SPACE,
///     &.{ "counter", &authority.bytes },
///     bump,
///     &my_program_id,
///     system_program_info,
/// );
/// ```
pub fn createAccountAtPda(
    payer: *const AccountInfo,
    new_account: *const AccountInfo,
    owner: *const PublicKey,
    space: usize,
    seeds: anytype,
    bump: u8,
    program_id: *const PublicKey,
    system_program_info: *const AccountInfo,
) InitError!void {
    _ = program_id; // Used for signing context

    // Validate payer is signer
    if (payer.is_signer == 0) {
        return InitError.PayerNotSigner;
    }

    // Validate new account is writable
    if (new_account.is_writable == 0) {
        return InitError.AccountNotWritable;
    }

    // Calculate rent-exempt balance
    const lamports = rentExemptBalance(space) catch {
        return InitError.RentUnavailable;
    };

    // Build seeds with bump for signing
    const SeedsType = @TypeOf(seeds);
    const seeds_len = @typeInfo(SeedsType).@"struct".fields.len;

    var seeds_with_bump: [seeds_len + 1][]const u8 = undefined;

    comptime var i = 0;
    inline while (i < seeds_len) : (i += 1) {
        seeds_with_bump[i] = seeds[i];
    }

    const bump_bytes = [_]u8{bump};
    seeds_with_bump[seeds_len] = &bump_bytes;

    // Build the create account instruction
    const ix = Instruction.from(.{
        .program_id = &system_program.id,
        .accounts = &[_]sdk_account.Account.Param{
            .{
                .id = payer.id,
                .is_signer = true,
                .is_writable = true,
            },
            .{
                .id = new_account.id,
                .is_signer = true, // PDA is signer via invoke_signed
                .is_writable = true,
            },
        },
        .data = &buildCreateAccountData(lamports, space, owner),
    });

    // Build signer seeds array for invoke_signed
    const signer_seeds: [1][]const []const u8 = .{&seeds_with_bump};

    // Invoke the system program with PDA signer
    const result = ix.invokeSigned(
        &[_]AccountInfo{ payer.*, new_account.*, system_program_info.* },
        &signer_seeds,
    );
    if (result != null) {
        return InitError.InvokeFailed;
    }
}

/// Build the data for a CreateAccount instruction
fn buildCreateAccountData(lamports: u64, space: usize, owner: *const PublicKey) [52]u8 {
    var data: [52]u8 = undefined;

    // Instruction index: 0 = CreateAccount (u32 little-endian)
    data[0] = 0;
    data[1] = 0;
    data[2] = 0;
    data[3] = 0;

    // Lamports (u64 little-endian)
    @memcpy(data[4..12], &std.mem.toBytes(lamports));

    // Space (u64 little-endian)
    @memcpy(data[12..20], &std.mem.toBytes(@as(u64, space)));

    // Owner (32 bytes)
    @memcpy(data[20..52], &owner.bytes);

    return data;
}

/// Check if an account is uninitialized (all zeros or empty)
pub fn isUninitialized(info: *const AccountInfo) bool {
    // Account with zero lamports is uninitialized
    if (info.lamports.* == 0) {
        return true;
    }

    // Account with no data and owned by system program is uninitialized
    if (info.data_len == 0 and info.owner_id.equals(system_program.id)) {
        return true;
    }

    return false;
}

/// Validate that an account is ready for initialization
pub fn validateForInit(info: *const AccountInfo) InitError!void {
    // Must be writable
    if (info.is_writable == 0) {
        return InitError.AccountNotWritable;
    }

    // Should not already be initialized
    if (!isUninitialized(info)) {
        return InitError.AccountAlreadyInitialized;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "rentExemptBalanceDefault calculation" {
    // Test with Solana's default rent values
    // Default: ~3480 lamports per byte per year (1_000_000_000 / 100 * 365 / 1024 / 1024)
    // Exemption threshold: 2.0
    // 128 (overhead) + 100 (space) = 228 bytes
    // 228 * 3480 * 2 = 1_586_880
    const balance = rentExemptBalanceDefault(100);
    // Verify the balance is calculated correctly (> 0 and reasonable)
    try std.testing.expect(balance > 0);
    try std.testing.expect(balance == 228 * Rent.default_lamports_per_byte_year * @as(u64, @intFromFloat(Rent.default_exemption_threshold)));
}

test "rentExemptBalanceDefault zero space" {
    // Just overhead: 128 * ~3480 * 2 = 890_880
    const balance = rentExemptBalanceDefault(0);
    // Verify the balance is calculated correctly for overhead only
    try std.testing.expect(balance > 0);
    try std.testing.expect(balance == Rent.account_storage_overhead * Rent.default_lamports_per_byte_year * @as(u64, @intFromFloat(Rent.default_exemption_threshold)));
}

test "buildCreateAccountData format" {
    const owner = PublicKey.from([_]u8{0xAB} ** 32);
    const data = buildCreateAccountData(1_000_000, 165, &owner);

    // Check instruction index (0 for CreateAccount)
    try std.testing.expectEqual(@as(u8, 0), data[0]);
    try std.testing.expectEqual(@as(u8, 0), data[1]);
    try std.testing.expectEqual(@as(u8, 0), data[2]);
    try std.testing.expectEqual(@as(u8, 0), data[3]);

    // Check lamports (little-endian u64)
    const lamports = std.mem.readInt(u64, data[4..12], .little);
    try std.testing.expectEqual(@as(u64, 1_000_000), lamports);

    // Check space (little-endian u64)
    const space = std.mem.readInt(u64, data[12..20], .little);
    try std.testing.expectEqual(@as(u64, 165), space);

    // Check owner
    try std.testing.expectEqualSlices(u8, &owner.bytes, data[20..52]);
}

test "isUninitialized with zero lamports" {
    var id = PublicKey.default();
    var owner = system_program.id;
    var lamports: u64 = 0;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(isUninitialized(&info));
}

test "isUninitialized with system program owner and no data" {
    var id = PublicKey.default();
    var owner = system_program.id;
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(isUninitialized(&info));
}

test "isUninitialized returns false for initialized account" {
    var id = PublicKey.default();
    // Use Token Program as owner - different from system program
    var owner = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var lamports: u64 = 1000;
    var data: [100]u8 = undefined;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(!isUninitialized(&info));
}

test "validateForInit fails for non-writable" {
    var id = PublicKey.default();
    var owner = system_program.id;
    var lamports: u64 = 0;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(InitError.AccountNotWritable, validateForInit(&info));
}

test "validateForInit fails for already initialized" {
    var id = PublicKey.default();
    // Use Token Program - account is initialized (not system program, has data)
    var owner = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var lamports: u64 = 1000;
    var data: [100]u8 = undefined;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(InitError.AccountAlreadyInitialized, validateForInit(&info));
}

test "validateForInit succeeds for uninitialized writable account" {
    var id = PublicKey.default();
    var owner = system_program.id;
    var lamports: u64 = 0;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try validateForInit(&info);
}
