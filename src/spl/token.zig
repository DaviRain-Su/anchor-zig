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

// ============================================================================
// CPI Helpers using Instruction.invoke
// ============================================================================

const Instruction = sol.instruction.Instruction;
const AccountInfo = sol.account.Account.Info;
const AccountParam = sol.account.Account.Param;

/// Transfer tokens via CPI
/// Accepts Account.Info directly for use with ProgramContext
pub fn transfer(
    source: AccountInfo,
    destination: AccountInfo,
    authority: AccountInfo,
    amount: u64,
) !void {
    // Build account params for CPI
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = destination.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    // Build instruction data
    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.Transfer);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    // Create CPI instruction
    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    // Build account infos for invoke
    const account_infos = [_]AccountInfo{ source, destination, authority };

    // Invoke SPL Token Program
    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Mint tokens via CPI
pub fn mintTo(
    mint: AccountInfo,
    destination: AccountInfo,
    authority: AccountInfo,
    amount: u64,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
        .{ .id = destination.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.MintTo);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ mint, destination, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Burn tokens via CPI
pub fn burn(
    source: AccountInfo,
    mint: AccountInfo,
    authority: AccountInfo,
    amount: u64,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.Burn);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, mint, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Close token account via CPI  
pub fn close(
    account_to_close: AccountInfo,
    destination: AccountInfo,
    authority: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account_to_close.id, .is_writable = true, .is_signer = false },
        .{ .id = destination.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.CloseAccount)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account_to_close, destination, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Approve delegate to transfer tokens via CPI
///
/// Allows `delegate` to transfer up to `amount` tokens from `source`.
pub fn approve(
    source: AccountInfo,
    delegate: AccountInfo,
    authority: AccountInfo,
    amount: u64,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = delegate.id, .is_writable = false, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.Approve);
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, delegate, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Revoke delegate approval via CPI
///
/// Removes any delegate approval on the token account.
pub fn revoke(
    source: AccountInfo,
    authority: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.Revoke)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Authority type for setAuthority instruction
pub const AuthorityType = enum(u8) {
    /// Authority to mint tokens
    MintTokens = 0,
    /// Authority to freeze token accounts
    FreezeAccount = 1,
    /// Authority over a token account (owner)
    AccountOwner = 2,
    /// Authority to close a token account
    CloseAccount = 3,
};

/// Set new authority on account or mint via CPI
///
/// Changes the authority of `account` from `current_authority` to `new_authority`.
/// If `new_authority` is null, the authority is removed permanently.
pub fn setAuthority(
    account: AccountInfo,
    current_authority: AccountInfo,
    authority_type: AuthorityType,
    new_authority: ?*const PublicKey,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = current_authority.id, .is_writable = false, .is_signer = true },
    };

    // Data: instruction (1) + authority_type (1) + COption<Pubkey> (1 + 32)
    var data: [35]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.SetAuthority);
    data[1] = @intFromEnum(authority_type);
    
    if (new_authority) |auth| {
        data[2] = 1; // COption::Some
        @memcpy(data[3..35], &auth.bytes);
    } else {
        data[2] = 0; // COption::None
        @memset(data[3..35], 0);
    }

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, current_authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Freeze token account via CPI
///
/// Prevents any transfers from the frozen account until thawed.
/// Requires freeze authority on the mint.
pub fn freezeAccount(
    account: AccountInfo,
    mint: AccountInfo,
    freeze_authority: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
        .{ .id = freeze_authority.id, .is_writable = false, .is_signer = true },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.FreezeAccount)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, mint, freeze_authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Thaw (unfreeze) token account via CPI
///
/// Re-enables transfers from a frozen account.
/// Requires freeze authority on the mint.
pub fn thawAccount(
    account: AccountInfo,
    mint: AccountInfo,
    freeze_authority: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
        .{ .id = freeze_authority.id, .is_writable = false, .is_signer = true },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.ThawAccount)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, mint, freeze_authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Initialize a new mint via CPI
///
/// Creates a new token mint with the given decimals and authorities.
/// The `mint` account must be pre-allocated with `Mint.SIZE` bytes.
pub fn initializeMint(
    mint: AccountInfo,
    rent_sysvar: AccountInfo,
    decimals: u8,
    mint_authority: *const PublicKey,
    freeze_authority: ?*const PublicKey,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
        .{ .id = rent_sysvar.id, .is_writable = false, .is_signer = false },
    };

    // Data: instruction (1) + decimals (1) + mint_authority (32) + COption<freeze_authority> (1 + 32)
    var data: [67]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.InitializeMint);
    data[1] = decimals;
    @memcpy(data[2..34], &mint_authority.bytes);
    
    if (freeze_authority) |auth| {
        data[34] = 1; // COption::Some
        @memcpy(data[35..67], &auth.bytes);
    } else {
        data[34] = 0; // COption::None
        @memset(data[35..67], 0);
    }

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ mint, rent_sysvar };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Initialize a new mint via CPI (version 2, no rent sysvar needed)
///
/// Creates a new token mint with the given decimals and authorities.
/// The `mint` account must be pre-allocated with `Mint.SIZE` bytes.
pub fn initializeMint2(
    mint: AccountInfo,
    decimals: u8,
    mint_authority: *const PublicKey,
    freeze_authority: ?*const PublicKey,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
    };

    // Data: instruction (1) + decimals (1) + mint_authority (32) + COption<freeze_authority> (1 + 32)
    var data: [67]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.InitializeMint2);
    data[1] = decimals;
    @memcpy(data[2..34], &mint_authority.bytes);
    
    if (freeze_authority) |auth| {
        data[34] = 1; // COption::Some
        @memcpy(data[35..67], &auth.bytes);
    } else {
        data[34] = 0; // COption::None
        @memset(data[35..67], 0);
    }

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{mint};

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Initialize a new token account via CPI
///
/// Creates a new token account for the given mint and owner.
/// The `account` must be pre-allocated with `TokenAccountData.SIZE` bytes.
pub fn initializeAccount(
    account: AccountInfo,
    mint: AccountInfo,
    owner: AccountInfo,
    rent_sysvar: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
        .{ .id = owner.id, .is_writable = false, .is_signer = false },
        .{ .id = rent_sysvar.id, .is_writable = false, .is_signer = false },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.InitializeAccount)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, mint, owner, rent_sysvar };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Initialize a new token account via CPI (version 2, owner in instruction data)
///
/// Creates a new token account for the given mint and owner.
/// The `account` must be pre-allocated with `TokenAccountData.SIZE` bytes.
pub fn initializeAccount2(
    account: AccountInfo,
    mint: AccountInfo,
    owner: *const PublicKey,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
    };

    // Data: instruction (1) + owner (32)
    var data: [33]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.InitializeAccount2);
    @memcpy(data[1..33], &owner.bytes);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, mint };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Initialize a new token account via CPI (version 3, owner in instruction data, no rent check)
///
/// Creates a new token account for the given mint and owner.
/// The `account` must be pre-allocated with `TokenAccountData.SIZE` bytes.
pub fn initializeAccount3(
    account: AccountInfo,
    mint: AccountInfo,
    owner: *const PublicKey,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = account.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
    };

    // Data: instruction (1) + owner (32)
    var data: [33]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.InitializeAccount3);
    @memcpy(data[1..33], &owner.bytes);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ account, mint };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Sync native SOL balance via CPI
///
/// Synchronizes the token account's amount with its lamport balance.
/// Only valid for native (wrapped SOL) token accounts.
pub fn syncNative(
    native_account: AccountInfo,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = native_account.id, .is_writable = true, .is_signer = false },
    };

    const data = [_]u8{@intFromEnum(TokenInstruction.SyncNative)};

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{native_account};

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Transfer tokens with checked decimals via CPI
///
/// Like `transfer`, but verifies the mint decimals match.
/// This is the recommended way to transfer tokens.
pub fn transferChecked(
    source: AccountInfo,
    mint: AccountInfo,
    destination: AccountInfo,
    authority: AccountInfo,
    amount: u64,
    decimals: u8,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
        .{ .id = destination.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    // Data: instruction (1) + amount (8) + decimals (1)
    var data: [10]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.TransferChecked);
    std.mem.writeInt(u64, data[1..9], amount, .little);
    data[9] = decimals;

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, mint, destination, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Approve delegate with checked decimals via CPI
///
/// Like `approve`, but verifies the mint decimals match.
pub fn approveChecked(
    source: AccountInfo,
    mint: AccountInfo,
    delegate: AccountInfo,
    authority: AccountInfo,
    amount: u64,
    decimals: u8,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = false, .is_signer = false },
        .{ .id = delegate.id, .is_writable = false, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    // Data: instruction (1) + amount (8) + decimals (1)
    var data: [10]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.ApproveChecked);
    std.mem.writeInt(u64, data[1..9], amount, .little);
    data[9] = decimals;

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, mint, delegate, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Mint tokens with checked decimals via CPI
///
/// Like `mintTo`, but verifies the mint decimals match.
pub fn mintToChecked(
    mint: AccountInfo,
    destination: AccountInfo,
    authority: AccountInfo,
    amount: u64,
    decimals: u8,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
        .{ .id = destination.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    // Data: instruction (1) + amount (8) + decimals (1)
    var data: [10]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.MintToChecked);
    std.mem.writeInt(u64, data[1..9], amount, .little);
    data[9] = decimals;

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ mint, destination, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
}

/// Burn tokens with checked decimals via CPI
///
/// Like `burn`, but verifies the mint decimals match.
pub fn burnChecked(
    source: AccountInfo,
    mint: AccountInfo,
    authority: AccountInfo,
    amount: u64,
    decimals: u8,
) !void {
    const account_params = [_]AccountParam{
        .{ .id = source.id, .is_writable = true, .is_signer = false },
        .{ .id = mint.id, .is_writable = true, .is_signer = false },
        .{ .id = authority.id, .is_writable = false, .is_signer = true },
    };

    // Data: instruction (1) + amount (8) + decimals (1)
    var data: [10]u8 = undefined;
    data[0] = @intFromEnum(TokenInstruction.BurnChecked);
    std.mem.writeInt(u64, data[1..9], amount, .little);
    data[9] = decimals;

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{ source, mint, authority };

    if (ix.invoke(&account_infos)) |err| {
        _ = err;
        return error.CpiFailed;
    }
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
