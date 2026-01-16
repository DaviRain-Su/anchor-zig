//! Zig implementation of Anchor realloc constraint
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/realloc.rs
//!
//! Resizes account data, handling rent payments and refunds automatically.
//! When growing an account, additional rent is charged from the payer.
//! When shrinking an account, excess rent is refunded to the payer.
//!
//! ## Example
//! ```zig
//! const Dynamic = anchor.Account(DynamicData, .{
//!     .discriminator = anchor.accountDiscriminator("Dynamic"),
//!     .realloc = .{
//!         .payer = "payer",
//!         .zero_init = true,
//!     },
//! });
//!
//! fn resize(ctx: anchor.Context(ResizeAccounts), new_size: usize) !void {
//!     try anchor.realloc.reallocAccount(
//!         ctx.accounts.dynamic.toAccountInfo(),
//!         new_size,
//!         ctx.accounts.payer.toAccountInfo(),
//!         true,
//!     );
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const sdk_account = sol.account;
const rent_mod = sol.rent;
const PublicKey = sol.PublicKey;

const AccountInfo = sdk_account.Account.Info;
const Rent = rent_mod.Rent;

/// Maximum account data size (10 MB)
pub const MAX_ACCOUNT_SIZE: usize = 10 * 1024 * 1024;

/// Maximum single realloc increase (10 KB per transaction)
/// This matches Solana runtime's limitation on account growth per transaction.
pub const MAX_REALLOC_INCREASE: usize = 10 * 1024;

/// Account reallocation errors
pub const ReallocError = error{
    /// Account is not writable
    AccountNotWritable,

    /// Payer is not a signer (required for growing account)
    PayerNotSigner,

    /// New size exceeds maximum allowed (10 MB)
    SizeExceedsMax,

    /// Cannot reallocate to zero size (use close instead)
    ZeroSize,

    /// Payer has insufficient lamports for additional rent
    InsufficientPayer,

    /// Account shrinking would leave insufficient rent
    InsufficientRent,

    /// Payer is required when growing an account that needs additional rent
    PayerRequired,

    /// Single realloc increase exceeds maximum (10 KB)
    ReallocIncreaseTooLarge,
};

/// Realloc configuration for AccountConfig
pub const ReallocConfig = struct {
    /// Payer account field name for additional rent
    ///
    /// Required when the account may grow. The payer will pay
    /// for additional rent when growing, and receive refunds
    /// when shrinking.
    payer: ?[]const u8 = null,

    /// Zero-initialize new space when growing
    ///
    /// When true, newly allocated bytes are set to zero.
    /// Defaults to true for security.
    zero_init: bool = true,
};

/// Reallocate account data to a new size
///
/// Handles rent calculations:
/// - Growing: charges additional rent from payer
/// - Shrinking: refunds excess rent to payer
/// - Same size: no-op
///
/// Note: In the actual Solana runtime, this would use the
/// sol_realloc syscall. This implementation handles the
/// lamport transfers and data initialization.
///
/// Example:
/// ```zig
/// // Grow account
/// try reallocAccount(&account_info, new_size, &payer_info, true);
///
/// // Shrink account (payer receives refund)
/// try reallocAccount(&account_info, smaller_size, &payer_info, false);
/// ```
pub fn reallocAccount(
    account: *const AccountInfo,
    new_size: usize,
    payer: ?*const AccountInfo,
    zero_init: bool,
) ReallocError!void {
    // Validate account is writable
    if (account.is_writable == 0) {
        return ReallocError.AccountNotWritable;
    }

    // Validate new size
    if (new_size == 0) {
        return ReallocError.ZeroSize;
    }

    if (new_size > MAX_ACCOUNT_SIZE) {
        return ReallocError.SizeExceedsMax;
    }

    const old_size = account.data_len;

    // No change needed
    if (new_size == old_size) {
        return;
    }

    // Calculate rent difference
    const rent = Rent.getOrDefault();
    const old_rent = rent.getMinimumBalance(old_size);
    const new_rent = rent.getMinimumBalance(new_size);

    if (new_size > old_size) {
        // Check single realloc increase limit (10 KB)
        const increase = new_size - old_size;
        if (increase > MAX_REALLOC_INCREASE) {
            return ReallocError.ReallocIncreaseTooLarge;
        }

        // Growing: need more rent
        const additional_rent = new_rent - old_rent;

        if (additional_rent > 0) {
            // Payer is required when growing requires additional rent
            const p = payer orelse return ReallocError.PayerRequired;

            // Validate payer is signer
            if (p.is_signer == 0) {
                return ReallocError.PayerNotSigner;
            }

            // Check payer has sufficient lamports
            if (p.lamports.* < additional_rent) {
                return ReallocError.InsufficientPayer;
            }

            // Transfer from payer to account
            p.lamports.* -= additional_rent;
            account.lamports.* += additional_rent;
        }

        // Zero-init new space if requested and account data is accessible
        if (zero_init) {
            // Note: In actual runtime, the data slice would be extended
            // For testing, we assume data buffer is large enough
            if (account.data_len < new_size) {
                // Data buffer extended by runtime
                @memset(account.data[old_size..new_size], 0);
            }
        }
    } else {
        // Shrinking: refund excess rent
        const refund = old_rent - new_rent;

        if (refund > 0) {
            // Check account has enough lamports after refund
            if (account.lamports.* < refund) {
                return ReallocError.InsufficientRent;
            }

            if (payer) |p| {
                // Transfer refund to payer
                account.lamports.* -= refund;
                p.lamports.* += refund;
            }
        }
    }

    // Update data length
    // Note: This is a simplification. In actual SBF runtime,
    // sol_realloc would handle the memory reallocation.
    @as(*usize, @ptrCast(@constCast(&account.data_len))).* = new_size;
}

/// Calculate the rent difference for a realloc operation
///
/// Returns:
/// - Positive value: amount payer needs to pay (growing)
/// - Negative value: amount to refund (shrinking)
/// - Zero: no rent change
pub fn calculateRentDiff(old_size: usize, new_size: usize) i64 {
    const rent = Rent.getOrDefault();
    const old_rent = rent.getMinimumBalance(old_size);
    const new_rent = rent.getMinimumBalance(new_size);

    return @as(i64, @intCast(new_rent)) - @as(i64, @intCast(old_rent));
}

/// Calculate rent required for a given data size
pub fn rentForSize(size: usize) u64 {
    const rent = Rent.getOrDefault();
    return rent.getMinimumBalance(size);
}

/// Check if a realloc operation would require additional payment
pub fn requiresPayment(old_size: usize, new_size: usize) bool {
    return new_size > old_size;
}

/// Check if a realloc operation would produce a refund
pub fn producesRefund(old_size: usize, new_size: usize) bool {
    return new_size < old_size;
}

/// Validate a realloc operation without executing it
pub fn validateRealloc(
    account: *const AccountInfo,
    new_size: usize,
    payer: ?*const AccountInfo,
) ReallocError!void {
    if (account.is_writable == 0) {
        return ReallocError.AccountNotWritable;
    }

    if (new_size == 0) {
        return ReallocError.ZeroSize;
    }

    if (new_size > MAX_ACCOUNT_SIZE) {
        return ReallocError.SizeExceedsMax;
    }

    const old_size = account.data_len;
    if (new_size == old_size) {
        return;
    }

    const rent = Rent.getOrDefault();
    const old_rent = rent.getMinimumBalance(old_size);
    const new_rent = rent.getMinimumBalance(new_size);

    if (new_size > old_size) {
        // Check single realloc increase limit (10 KB)
        const increase = new_size - old_size;
        if (increase > MAX_REALLOC_INCREASE) {
            return ReallocError.ReallocIncreaseTooLarge;
        }

        const additional_rent = new_rent - old_rent;
        if (additional_rent > 0) {
            // Payer is required when growing requires additional rent
            const p = payer orelse return ReallocError.PayerRequired;
            if (p.is_signer == 0) {
                return ReallocError.PayerNotSigner;
            }
            if (p.lamports.* < additional_rent) {
                return ReallocError.InsufficientPayer;
            }
        }
    } else {
        const refund = old_rent - new_rent;
        if (refund > 0 and account.lamports.* < refund) {
            return ReallocError.InsufficientRent;
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "MAX_ACCOUNT_SIZE is 10 MB" {
    try std.testing.expectEqual(@as(usize, 10 * 1024 * 1024), MAX_ACCOUNT_SIZE);
}

test "reallocAccount fails when account not writable" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [100]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(ReallocError.AccountNotWritable, reallocAccount(&account_info, 100, null, true));
}

test "reallocAccount fails for zero size" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [100]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(ReallocError.ZeroSize, reallocAccount(&account_info, 0, null, true));
}

test "reallocAccount fails for size exceeding max" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [100]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(ReallocError.SizeExceedsMax, reallocAccount(&account_info, MAX_ACCOUNT_SIZE + 1, null, true));
}

test "reallocAccount succeeds for same size (no-op)" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [100]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try reallocAccount(&account_info, 50, null, true);

    // Lamports unchanged
    try std.testing.expectEqual(@as(u64, 1_000_000), lamports);
}

test "reallocAccount growing requires payer signer" {
    var account_id = PublicKey.default();
    var payer_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var account_lamports: u64 = 1_000_000;
    var payer_lamports: u64 = 10_000_000;
    var data: [200]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0, // Not a signer
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(ReallocError.PayerNotSigner, reallocAccount(&account_info, 100, &payer_info, true));
}

test "reallocAccount growing transfers rent from payer" {
    var account_id = PublicKey.default();
    var payer_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var account_lamports: u64 = 1_000_000;
    var payer_lamports: u64 = 10_000_000;
    var data: [200]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1, // Is signer
        .is_writable = 1,
        .is_executable = 0,
    };

    const old_account_lamports = account_lamports;
    const old_payer_lamports = payer_lamports;

    try reallocAccount(&account_info, 100, &payer_info, true);

    // Account should have more lamports
    try std.testing.expect(account_lamports > old_account_lamports);
    // Payer should have fewer lamports
    try std.testing.expect(payer_lamports < old_payer_lamports);
    // Total lamports unchanged
    try std.testing.expectEqual(old_account_lamports + old_payer_lamports, account_lamports + payer_lamports);
}

test "reallocAccount shrinking refunds rent to payer" {
    var account_id = PublicKey.default();
    var payer_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var account_lamports: u64 = 10_000_000;
    var payer_lamports: u64 = 1_000_000;
    var data: [200]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 100,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    const old_account_lamports = account_lamports;
    const old_payer_lamports = payer_lamports;

    try reallocAccount(&account_info, 50, &payer_info, false);

    // Account should have fewer lamports
    try std.testing.expect(account_lamports < old_account_lamports);
    // Payer should have more lamports (refund)
    try std.testing.expect(payer_lamports > old_payer_lamports);
    // Total lamports unchanged
    try std.testing.expectEqual(old_account_lamports + old_payer_lamports, account_lamports + payer_lamports);
}

test "calculateRentDiff returns positive for growing" {
    const diff = calculateRentDiff(50, 100);
    try std.testing.expect(diff > 0);
}

test "calculateRentDiff returns negative for shrinking" {
    const diff = calculateRentDiff(100, 50);
    try std.testing.expect(diff < 0);
}

test "calculateRentDiff returns zero for same size" {
    const diff = calculateRentDiff(100, 100);
    try std.testing.expectEqual(@as(i64, 0), diff);
}

test "requiresPayment returns true for growing" {
    try std.testing.expect(requiresPayment(50, 100));
    try std.testing.expect(!requiresPayment(100, 50));
    try std.testing.expect(!requiresPayment(100, 100));
}

test "producesRefund returns true for shrinking" {
    try std.testing.expect(producesRefund(100, 50));
    try std.testing.expect(!producesRefund(50, 100));
    try std.testing.expect(!producesRefund(100, 100));
}

test "rentForSize returns non-zero for non-zero size" {
    const rent = rentForSize(100);
    try std.testing.expect(rent > 0);
}

test "validateRealloc catches errors without executing" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [100]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(ReallocError.AccountNotWritable, validateRealloc(&account_info, 100, null));
}

test "reallocAccount fails when payer is null but required for rent" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;
    var data: [200]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 50,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    // Growing account without payer should fail with PayerRequired
    try std.testing.expectError(ReallocError.PayerRequired, reallocAccount(&account_info, 100, null, true));
}

test "reallocAccount fails when increase exceeds 10KB limit" {
    var account_id = PublicKey.default();
    var payer_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var account_lamports: u64 = 1_000_000_000;
    var payer_lamports: u64 = 1_000_000_000;
    var data: [20000]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 100,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    // Trying to grow by more than 10KB should fail
    const new_size = 100 + MAX_REALLOC_INCREASE + 1;
    try std.testing.expectError(ReallocError.ReallocIncreaseTooLarge, reallocAccount(&account_info, new_size, &payer_info, true));
}

test "reallocAccount succeeds when increase is exactly 10KB" {
    var account_id = PublicKey.default();
    var payer_id = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var account_lamports: u64 = 1_000_000_000;
    var payer_lamports: u64 = 1_000_000_000;
    var data: [20000]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &account_lamports,
        .data_len = 100,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    // Growing by exactly 10KB should succeed
    const new_size = 100 + MAX_REALLOC_INCREASE;
    try reallocAccount(&account_info, new_size, &payer_info, true);
}

test "reallocAccount shrinking succeeds without payer" {
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 10_000_000;
    var data: [200]u8 = undefined;

    const account_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 100,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    // Shrinking should succeed without payer (refund is just lost)
    try reallocAccount(&account_info, 50, null, false);
}

test "MAX_REALLOC_INCREASE is 10 KB" {
    try std.testing.expectEqual(@as(usize, 10 * 1024), MAX_REALLOC_INCREASE);
}
