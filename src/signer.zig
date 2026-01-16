//! Zig implementation of Anchor Signer account type
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/signer.rs
//!
//! Signer represents an account that must be a signer of the transaction.
//! It does not read or deserialize account data - it only validates that
//! the account signed the transaction.
//!
//! ## Example
//! ```zig
//! const MyAccounts = struct {
//!     authority: anchor.Signer,
//!     payer: anchor.SignerMut,
//! };
//!
//! // In instruction handler:
//! const authority_key = ctx.accounts.authority.key();
//! ```

const std = @import("std");
const anchor_error = @import("error.zig");
const sol = @import("solana_program_sdk");

// Import from parent SDK
const sdk_account = sol.account;
const PublicKey = sol.PublicKey;

const AnchorError = anchor_error.AnchorError;
const AccountInfo = sdk_account.Account.Info;

/// Signer account type
///
/// Validates that an account is a signer of the transaction.
/// Does not read or deserialize account data.
///
/// Anchor equivalent: `Signer<'info>`
pub const Signer = struct {
    /// The account info
    info: *const AccountInfo,

    /// Load and validate a signer account
    ///
    /// Returns error if account is not a signer.
    pub fn load(info: *const AccountInfo) !Signer {
        if (info.is_signer == 0) {
            return error.ConstraintSigner;
        }

        return Signer{ .info = info };
    }

    /// Get the public key
    pub fn key(self: Signer) *const PublicKey {
        return self.info.id;
    }

    /// Get the underlying account info
    pub fn toAccountInfo(self: Signer) *const AccountInfo {
        return self.info;
    }

    /// Get the lamports balance
    pub fn lamports(self: Signer) u64 {
        return self.info.lamports.*;
    }

    /// Check if account is writable
    pub fn isMut(self: Signer) bool {
        return self.info.is_writable != 0;
    }
};

/// Signer account that must also be mutable
///
/// Common for payer accounts that need to transfer lamports.
///
/// Anchor equivalent: `Signer<'info>` with `#[account(mut)]`
pub const SignerMut = struct {
    /// The account info
    info: *const AccountInfo,

    /// Load and validate a mutable signer account
    ///
    /// Returns error if account is not a signer or not writable.
    pub fn load(info: *const AccountInfo) !SignerMut {
        if (info.is_signer == 0) {
            return error.ConstraintSigner;
        }
        if (info.is_writable == 0) {
            return error.ConstraintMut;
        }

        return SignerMut{ .info = info };
    }

    /// Get the public key
    pub fn key(self: SignerMut) *const PublicKey {
        return self.info.id;
    }

    /// Get the underlying account info
    pub fn toAccountInfo(self: SignerMut) *const AccountInfo {
        return self.info;
    }

    /// Get the lamports balance
    pub fn lamports(self: SignerMut) u64 {
        return self.info.lamports.*;
    }
};

/// Configuration for signer validation
pub const SignerConfig = struct {
    /// Account must be writable
    mut: bool = false,
};

/// Configurable signer type
///
/// Use when you need runtime-configurable signer constraints.
pub fn SignerWith(comptime config: SignerConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,

        pub fn load(info: *const AccountInfo) !Self {
            // Must be signer
            if (info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            // Must be writable if mut constraint
            if (config.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }

            return Self{ .info = info };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }

        pub fn lamports(self: Self) u64 {
            return self.info.lamports.*;
        }

        pub fn isMut(self: Self) bool {
            return self.info.is_writable != 0;
        }
    };
}

/// Signer validation errors
pub const SignerError = error{
    ConstraintSigner,
    ConstraintMut,
};

// ============================================================================
// Tests
// ============================================================================

test "Signer.load accepts signer account" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const signer = try Signer.load(&info);
    try std.testing.expectEqual(&id, signer.key());
}

test "Signer.load rejects non-signer" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0, // Not a signer
        .is_writable = 0,
        .is_executable = 0,
    };

    try std.testing.expectError(error.ConstraintSigner, Signer.load(&info));
}

test "SignerMut.load accepts mutable signer" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    const signer = try SignerMut.load(&info);
    try std.testing.expectEqual(&id, signer.key());
}

test "SignerMut.load rejects non-writable signer" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(error.ConstraintMut, SignerMut.load(&info));
}

test "SignerWith configurable constraints" {
    const MutableSigner = SignerWith(.{ .mut = true });

    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    const signer = try MutableSigner.load(&info);
    try std.testing.expectEqual(&id, signer.key());
}

test "Signer.lamports returns balance" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 5_000_000_000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const signer = try Signer.load(&info);
    try std.testing.expectEqual(@as(u64, 5_000_000_000), signer.lamports());
}
