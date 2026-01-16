//! Zig implementation of Anchor close constraint
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/close.rs
//!
//! Closes an account by transferring all lamports to a destination account
//! and zeroing out the account data. The Solana runtime will automatically
//! garbage collect the account and assign ownership to the system program.
//!
//! ## Example
//! ```zig
//! const Closeable = anchor.Account(Data, .{
//!     .discriminator = anchor.accountDiscriminator("Closeable"),
//!     .close = "destination",
//! });
//!
//! fn closeMyAccount(ctx: anchor.Context(CloseAccounts)) !void {
//!     try anchor.close.closeAccount(
//!         ctx.accounts.closeable.toAccountInfo(),
//!         ctx.accounts.destination.toAccountInfo(),
//!     );
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const sdk_account = sol.account;
const PublicKey = sol.PublicKey;
const system_program = sol.system_program;

const AccountInfo = sdk_account.Account.Info;

/// Account closing errors
pub const CloseError = error{
    /// Account to close is not writable
    AccountNotWritable,

    /// Destination account is not writable
    DestinationNotWritable,

    /// Cannot close an account to itself
    CloseToSelf,

    /// Account has insufficient lamports (should not happen normally)
    InsufficientLamports,
};

/// Close an account, transferring all lamports to destination
///
/// This function:
/// 1. Validates both accounts are writable
/// 2. Validates account is not closing to itself
/// 3. Transfers all lamports from account to destination
/// 4. Zeros all account data
///
/// Note: The Solana runtime automatically:
/// - Sets account owner to system program when lamports become 0
/// - Garbage collects the account after the transaction
///
/// Example:
/// ```zig
/// try closeAccount(&account_info, &destination_info);
/// ```
pub fn closeAccount(
    account: *const AccountInfo,
    destination: *const AccountInfo,
) CloseError!void {
    // Validate account is writable
    if (account.is_writable == 0) {
        return CloseError.AccountNotWritable;
    }

    // Validate destination is writable
    if (destination.is_writable == 0) {
        return CloseError.DestinationNotWritable;
    }

    // Cannot close to self
    if (account.id.equals(destination.id.*)) {
        return CloseError.CloseToSelf;
    }

    // Transfer all lamports to destination
    const account_lamports = account.lamports.*;
    destination.lamports.* += account_lamports;
    account.lamports.* = 0;

    // Zero all account data (including discriminator)
    if (account.data_len > 0) {
        @memset(account.data[0..account.data_len], 0);
    }
}

/// Close an account using typed wrapper
///
/// Convenience wrapper for closing typed Account instances.
///
/// Example:
/// ```zig
/// try close(Vault, vault_account, &destination_info);
/// ```
pub fn close(
    comptime AccountType: type,
    account: AccountType,
    destination: *const AccountInfo,
) CloseError!void {
    return closeAccount(account.toAccountInfo(), destination);
}

/// Check if an account can be closed to a destination
///
/// Returns false if:
/// - Account is not writable
/// - Destination is not writable
/// - Account and destination are the same
pub fn canClose(
    account: *const AccountInfo,
    destination: *const AccountInfo,
) bool {
    if (account.is_writable == 0) return false;
    if (destination.is_writable == 0) return false;
    if (account.id.equals(destination.id.*)) return false;
    return true;
}

/// Get the lamports that would be transferred on close
pub fn getCloseRefund(account: *const AccountInfo) u64 {
    return account.lamports.*;
}

/// Check if account is already closed (zero lamports)
pub fn isClosed(account: *const AccountInfo) bool {
    return account.lamports.* == 0;
}

// ============================================================================
// Tests
// ============================================================================

test "closeAccount transfers all lamports and zeros data" {
    var account_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = system_program.id;
    var account_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;
    var data: [100]u8 = undefined;
    @memset(&data, 0xAB); // Fill with non-zero data

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    try closeAccount(&account_info, &dest_info);

    // Check lamports transferred
    try std.testing.expectEqual(@as(u64, 0), account_lamports);
    try std.testing.expectEqual(@as(u64, 1_500_000), dest_lamports);

    // Check data zeroed
    for (data) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "closeAccount fails when account not writable" {
    var account_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = system_program.id;
    var account_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(CloseError.AccountNotWritable, closeAccount(&account_info, &dest_info));
}

test "closeAccount fails when destination not writable" {
    var account_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = system_program.id;
    var account_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(CloseError.DestinationNotWritable, closeAccount(&account_info, &dest_info));
}

test "closeAccount fails when closing to self" {
    var account_id = PublicKey.default();
    var owner = system_program.id;
    var account_lamports: u64 = 1_000_000;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    // Same account as destination
    try std.testing.expectError(CloseError.CloseToSelf, closeAccount(&account_info, &account_info));
}

test "canClose returns true for valid close operation" {
    var account_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = system_program.id;
    var account_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(canClose(&account_info, &dest_info));
}

test "canClose returns false for invalid operations" {
    var account_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = system_program.id;
    var lamports: u64 = 1_000_000;

    // Account not writable
    const account_not_writable = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const dest_writable = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(!canClose(&account_not_writable, &dest_writable));

    // Destination not writable
    const account_writable = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_not_writable = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    try std.testing.expect(!canClose(&account_writable, &dest_not_writable));

    // Close to self
    try std.testing.expect(!canClose(&account_writable, &account_writable));
}

test "getCloseRefund returns account lamports" {
    var account_id = PublicKey.default();
    var owner = system_program.id;
    var lamports: u64 = 1_234_567;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectEqual(@as(u64, 1_234_567), getCloseRefund(&account_info));
}

test "isClosed returns true for zero lamports" {
    var account_id = PublicKey.default();
    var owner = system_program.id;
    var zero_lamports: u64 = 0;
    var non_zero_lamports: u64 = 1000;

    const closed_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &zero_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const open_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &non_zero_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expect(isClosed(&closed_info));
    try std.testing.expect(!isClosed(&open_info));
}
