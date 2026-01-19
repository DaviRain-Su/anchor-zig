//! anchor-zig SPL Token Integration
//!
//! Provides Anchor-style account types for SPL Token program.
//! Similar to Rust's `anchor_spl::token` module.
//!
//! ## Usage
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//! const spl = anchor.spl;
//!
//! // Define accounts using SPL Token types
//! const TransferAccounts = struct {
//!     source: spl.token.TokenAccount(.{ .mut = true }),
//!     destination: spl.token.TokenAccount(.{ .mut = true }),
//!     authority: zero.Signer(0),
//!     token_program: spl.token.Program,
//! };
//!
//! fn transfer(ctx: zero.Ctx(TransferAccounts)) !void {
//!     const args = ctx.args(struct { amount: u64 });
//!     try spl.token.transferCpi(.{
//!         .source = ctx.accounts.source,
//!         .destination = ctx.accounts.destination,
//!         .authority = ctx.accounts.authority,
//!         .amount = args.amount,
//!     });
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const sdk_token = sol.spl.token;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const AccountMeta = sol.instruction.AccountMeta;

// Re-export SDK types
pub const Mint = sdk_token.Mint;
pub const TokenAccountData = sdk_token.Account;
pub const AccountState = sdk_token.AccountState;
pub const TokenInstruction = sdk_token.TokenInstruction;
pub const COption = sdk_token.COption;
pub const TOKEN_PROGRAM_ID = sdk_token.TOKEN_PROGRAM_ID;

// ============================================================================
// Account Type Wrappers (for use in Accounts structs)
// ============================================================================

/// Options for TokenAccount
pub const TokenAccountOptions = struct {
    /// Account is mutable
    mut: bool = false,
    /// Expected mint (optional constraint)
    mint: ?PublicKey = null,
    /// Expected owner/authority (optional constraint)
    authority: ?PublicKey = null,
};

/// SPL Token Account wrapper for use in Accounts structs
///
/// Provides typed access to token account data with optional constraints.
///
/// Usage:
/// ```zig
/// const Accounts = struct {
///     source: TokenAccount(.{ .mut = true }),
///     destination: TokenAccount(.{ .mut = true }),
/// };
/// ```
pub fn TokenAccount(comptime options: TokenAccountOptions) type {
    return struct {
        /// The underlying account info
        info: Account,

        const Self = @This();

        /// Account data size
        pub const data_size = TokenAccountData.SIZE;

        /// Is this account writable
        pub const is_writable = options.mut;

        /// Constraints for validation
        pub const CONSTRAINTS = struct {
            pub const writable = options.mut;
            pub const mint = options.mint;
            pub const authority = options.authority;
        };

        /// Get the account info
        pub fn accountInfo(self: Self) Account {
            return self.info;
        }

        /// Get parsed token account data
        pub fn data(self: Self) !TokenAccountData {
            return TokenAccountData.unpackFromSlice(self.info.data());
        }

        /// Get account's mint
        pub fn mint(self: Self) PublicKey {
            return PublicKey.from(self.info.data()[0..32].*);
        }

        /// Get account's owner
        pub fn owner(self: Self) PublicKey {
            return PublicKey.from(self.info.data()[32..64].*);
        }

        /// Get account's balance
        pub fn amount(self: Self) u64 {
            return std.mem.readInt(u64, self.info.data()[64..72], .little);
        }

        /// Get account's state
        pub fn state(self: Self) AccountState {
            return AccountState.fromByte(self.info.data()[108]) orelse .Uninitialized;
        }

        /// Check if account is frozen
        pub fn isFrozen(self: Self) bool {
            return self.state() == .Frozen;
        }

        /// Check if account is native (wrapped SOL)
        pub fn isNative(self: Self) bool {
            return std.mem.readInt(u32, self.info.data()[109..113], .little) == 1;
        }

        /// Get the account pubkey
        pub fn key(self: Self) PublicKey {
            return self.info.id();
        }
    };
}

/// Options for MintAccount
pub const MintAccountOptions = struct {
    /// Account is mutable
    mut: bool = false,
    /// Expected mint authority (optional constraint)
    mint_authority: ?PublicKey = null,
};

/// SPL Token Mint wrapper for use in Accounts structs
pub fn MintAccount(comptime options: MintAccountOptions) type {
    return struct {
        info: Account,

        const Self = @This();

        pub const data_size = Mint.SIZE;
        pub const is_writable = options.mut;

        pub const CONSTRAINTS = struct {
            pub const writable = options.mut;
            pub const mint_authority = options.mint_authority;
        };

        pub fn accountInfo(self: Self) Account {
            return self.info;
        }

        pub fn data(self: Self) !Mint {
            return Mint.unpackFromSlice(self.info.data());
        }

        /// Get mint's supply
        pub fn supply(self: Self) u64 {
            return std.mem.readInt(u64, self.info.data()[36..44], .little);
        }

        /// Get mint's decimals
        pub fn decimals(self: Self) u8 {
            return self.info.data()[44];
        }

        /// Check if mint is initialized
        pub fn isInitialized(self: Self) bool {
            return self.info.data()[45] == 1;
        }

        /// Get mint authority (if set)
        pub fn mintAuthority(self: Self) ?PublicKey {
            if (std.mem.readInt(u32, self.info.data()[0..4], .little) == 1) {
                return PublicKey.from(self.info.data()[4..36].*);
            }
            return null;
        }

        pub fn key(self: Self) PublicKey {
            return self.info.id();
        }
    };
}

/// SPL Token Program marker type
pub const Program = struct {
    info: Account,

    const Self = @This();

    pub const data_size = 0;
    pub const is_writable = false;

    /// The SPL Token Program ID
    pub const ID = TOKEN_PROGRAM_ID;

    pub const CONSTRAINTS = struct {
        pub const address = TOKEN_PROGRAM_ID;
    };

    pub fn accountInfo(self: Self) Account {
        return self.info;
    }

    pub fn key(self: Self) PublicKey {
        return self.info.id();
    }
};

// ============================================================================
// CPI Helpers
// ============================================================================

// CPI helpers are defined below as generic functions

/// Transfer tokens via CPI
pub fn transfer(
    source: Account,
    destination: Account,
    authority: Account,
    amount: u64,
) !void {
    const account_metas = [_]AccountMeta{
        .{ .pubkey = source.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.id(), .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.Transfer);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const account_infos = [_]Account{ source, destination, authority };

    sol.invoke.invoke(
        &.{
            .program_id = &TOKEN_PROGRAM_ID,
            .accounts = &account_metas,
            .data = &data,
        },
        &account_infos,
    ) catch return error.CpiFailed;
}

/// Mint tokens via CPI
pub fn mintTo(
    mint: Account,
    destination: Account,
    authority: Account,
    amount: u64,
) !void {
    const account_metas = [_]AccountMeta{
        .{ .pubkey = mint.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.id(), .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.MintTo);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const account_infos = [_]Account{ mint, destination, authority };

    sol.invoke.invoke(
        &.{
            .program_id = &TOKEN_PROGRAM_ID,
            .accounts = &account_metas,
            .data = &data,
        },
        &account_infos,
    ) catch return error.CpiFailed;
}

/// Burn tokens via CPI
pub fn burn(
    source: Account,
    mint: Account,
    authority: Account,
    amount: u64,
) !void {
    const account_metas = [_]AccountMeta{
        .{ .pubkey = source.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = mint.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.id(), .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.Burn);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const account_infos = [_]Account{ source, mint, authority };

    sol.invoke.invoke(
        &.{
            .program_id = &TOKEN_PROGRAM_ID,
            .accounts = &account_metas,
            .data = &data,
        },
        &account_infos,
    ) catch return error.CpiFailed;
}

/// Close token account via CPI  
pub fn close(
    account_to_close: Account,
    destination: Account,
    authority: Account,
) !void {
    const account_metas = [_]AccountMeta{
        .{ .pubkey = account_to_close.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = destination.id(), .is_writable = true, .is_signer = false },
        .{ .pubkey = authority.id(), .is_writable = false, .is_signer = true },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.CloseAccount)};

    const account_infos = [_]Account{ account_to_close, destination, authority };

    sol.invoke.invoke(
        &.{
            .program_id = &TOKEN_PROGRAM_ID,
            .accounts = &account_metas,
            .data = &data,
        },
        &account_infos,
    ) catch return error.CpiFailed;
}

// ============================================================================
// Tests
// ============================================================================

test "TokenAccount data size" {
    try std.testing.expectEqual(@as(usize, 165), TokenAccount(.{}).data_size);
}

test "MintAccount data size" {
    try std.testing.expectEqual(@as(usize, 82), MintAccount(.{}).data_size);
}

test "Program ID" {
    try std.testing.expectEqual(TOKEN_PROGRAM_ID, Program.ID);
}
