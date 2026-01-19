//! SPL Token using anchor-zig framework
//!
//! This version uses dynamic account parsing (Context.load) because
//! SPL Token instructions have different account layouts with varying data sizes.
//!
//! Note: zero.Ctx is designed for STATIC account layouts where all account
//! data sizes are known at compile time. For programs like SPL Token where
//! different instructions have different accounts, use Context.load().

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const spl = anchor.spl;
const sol = anchor.sdk;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const Context = sol.context.Context;
const Rent = sol.rent.Rent;
const AccountState = spl.token.AccountState;

// Account sizes
const MINT_SIZE = 82;
const TOKEN_ACCOUNT_SIZE = 165;

// Constants
const NATIVE_MINT_ID = PublicKey.comptimeFromBase58("So11111111111111111111111111111111111111112");
const SYSTEM_PROGRAM_ID = PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// Handlers using SDK Context (dynamic account parsing)
// ============================================================================

fn initializeMint(program_id: *align(1) PublicKey, accounts: []const Account, data: []const u8) !void {
    _ = program_id;
    if (accounts.len < 2) return error.NotEnoughAccountKeys;
    
    const mint_acc = accounts[0];
    const rent_acc = accounts[1];
    
    const mint_data = mint_acc.data();
    if (mint_data.len != MINT_SIZE) return error.InvalidAccountData;
    if (mint_data[45] == 1) return error.AlreadyInUse;

    const rent: *align(1) const Rent.Data = @ptrCast(rent_acc.data());
    if (!rent_acc.id().equals(Rent.id)) return error.InvalidAccountData;
    if (!rent.isExempt(mint_acc.lamports().*, MINT_SIZE)) return error.NotRentExempt;

    // Parse args (skip 1-byte discriminant)
    if (data.len < 35) return error.InvalidInstructionData;
    const decimals = data[1];
    const mint_authority = PublicKey.from(data[2..34].*);
    const has_freeze = data.len >= 67 and data[34] == 1;
    
    std.mem.writeInt(u32, mint_data[0..4], 1, .little);
    @memcpy(mint_data[4..36], &mint_authority.bytes);
    std.mem.writeInt(u64, mint_data[36..44], 0, .little);
    mint_data[44] = decimals;
    mint_data[45] = 1;
    
    if (has_freeze) {
        std.mem.writeInt(u32, mint_data[46..50], 1, .little);
        @memcpy(mint_data[50..82], data[35..67]);
    } else {
        std.mem.writeInt(u32, mint_data[46..50], 0, .little);
        @memset(mint_data[50..82], 0);
    }
}

fn initializeAccount(program_id: *align(1) PublicKey, accounts: []const Account) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    
    const token_acc = accounts[0];
    const mint_acc = accounts[1];
    const owner = accounts[2];
    const rent_acc = accounts[3];

    const data = token_acc.data();
    if (data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    if (data[108] != @intFromEnum(AccountState.Uninitialized)) return error.AlreadyInUse;
    
    const rent: *align(1) const Rent.Data = @ptrCast(rent_acc.data());
    if (!rent.isExempt(token_acc.lamports().*, TOKEN_ACCOUNT_SIZE)) return error.NotRentExempt;

    @memcpy(data[0..32], &mint_acc.id().bytes);
    @memcpy(data[32..64], &owner.id().bytes);
    std.mem.writeInt(u64, data[64..72], 0, .little);
    std.mem.writeInt(u32, data[72..76], 0, .little);
    @memset(data[76..108], 0);
    data[108] = @intFromEnum(AccountState.Initialized);
    
    if (mint_acc.id().equals(NATIVE_MINT_ID)) {
        const rent_exempt_reserve = rent.getMinimumBalance(TOKEN_ACCOUNT_SIZE);
        std.mem.writeInt(u32, data[109..113], 1, .little);
        std.mem.writeInt(u64, data[113..121], rent_exempt_reserve, .little);
        if (rent_exempt_reserve > token_acc.lamports().*) return error.Overflow;
        std.mem.writeInt(u64, data[64..72], token_acc.lamports().* - rent_exempt_reserve, .little);
    } else {
        if (!mint_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (mint_acc.data()[45] != 1) return error.UninitializedState;
        std.mem.writeInt(u32, data[109..113], 0, .little);
        @memset(data[113..121], 0);
    }
    
    std.mem.writeInt(u64, data[121..129], 0, .little);
    std.mem.writeInt(u32, data[129..133], 0, .little);
    @memset(data[133..165], 0);
}

fn transfer(program_id: *align(1) PublicKey, accounts: []const Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const source = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const source_data = source.data();
    const dest_data = destination.data();
    
    if (source_data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    if (dest_data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    
    // Check states
    if (source_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (dest_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (source_data[108] == @intFromEnum(AccountState.Frozen)) return error.AccountFrozen;
    if (dest_data[108] == @intFromEnum(AccountState.Frozen)) return error.AccountFrozen;

    const source_amount = std.mem.readInt(u64, source_data[64..72], .little);
    if (source_amount < amount) return error.InsufficientFunds;
    
    if (!std.mem.eql(u8, source_data[0..32], dest_data[0..32])) return error.MintMismatch;

    if (!std.mem.eql(u8, source_data[32..64], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    const pre_amount = source_amount;
    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    const dest_amount = std.mem.readInt(u64, dest_data[64..72], .little);
    std.mem.writeInt(u64, dest_data[64..72], dest_amount + amount, .little);

    if (std.mem.readInt(u32, source_data[109..113], .little) == 1) {
        source.lamports().* -= amount;
        destination.lamports().* += amount;
    }

    if (pre_amount == source_amount) {
        if (!source.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!destination.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn mintTo(program_id: *align(1) PublicKey, accounts: []const Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const mint = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const mint_data = mint.data();
    const dest_data = destination.data();
    
    if (mint_data.len != MINT_SIZE) return error.InvalidAccountData;
    if (dest_data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    
    if (mint_data[45] != 1) return error.UninitializedState;
    if (dest_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;

    if (std.mem.readInt(u32, dest_data[109..113], .little) == 1) return error.NativeNotSupported;
    if (!std.mem.eql(u8, &mint.id().bytes, dest_data[0..32])) return error.MintMismatch;

    if (std.mem.readInt(u32, mint_data[0..4], .little) == 0) return error.FixedSupply;
    if (!std.mem.eql(u8, mint_data[4..36], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    if (amount == 0) {
        if (!mint.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!destination.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }

    const supply = std.mem.readInt(u64, mint_data[36..44], .little);
    const new_supply = @addWithOverflow(supply, amount);
    if (new_supply[1] != 0) return error.Overflow;
    std.mem.writeInt(u64, mint_data[36..44], new_supply[0], .little);
    
    const dest_amount = std.mem.readInt(u64, dest_data[64..72], .little);
    std.mem.writeInt(u64, dest_data[64..72], dest_amount + amount, .little);
}

fn burn(program_id: *align(1) PublicKey, accounts: []const Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const source = accounts[0];
    const mint = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const source_data = source.data();
    const mint_data = mint.data();
    
    if (source_data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    if (mint_data.len != MINT_SIZE) return error.InvalidAccountData;
    
    if (source_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (mint_data[45] != 1) return error.UninitializedState;

    if (std.mem.readInt(u32, source_data[109..113], .little) == 1) return error.NativeNotSupported;
    if (!std.mem.eql(u8, &mint.id().bytes, source_data[0..32])) return error.MintMismatch;
    
    const source_amount = std.mem.readInt(u64, source_data[64..72], .little);
    if (source_amount < amount) return error.InsufficientFunds;

    if (!std.mem.eql(u8, source_data[32..64], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    const supply = std.mem.readInt(u64, mint_data[36..44], .little);
    std.mem.writeInt(u64, mint_data[36..44], supply - amount, .little);

    if (amount == 0) {
        if (!mint.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!source.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn closeAccount(program_id: *align(1) PublicKey, accounts: []const Account) !void {
    _ = program_id;
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    
    const account = accounts[0];
    const destination = accounts[1];
    const authority = accounts[2];

    const data = account.data();
    if (data.len != TOKEN_ACCOUNT_SIZE) return error.InvalidAccountData;
    
    if (data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;

    const is_native = std.mem.readInt(u32, data[109..113], .little) == 1;
    const amount = std.mem.readInt(u64, data[64..72], .little);
    if (!is_native and amount != 0) return error.NonNativeHasBalance;

    const close_auth_tag = std.mem.readInt(u32, data[129..133], .little);
    const expected: *const [32]u8 = if (close_auth_tag == 1) data[133..165] else data[32..64];

    if (!std.mem.eql(u8, expected, &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    destination.lamports().* += account.lamports().*;
    account.lamports().* = 0;
    account.assign(SYSTEM_PROGRAM_ID);
    account.reallocUnchecked(0);

    if (destination.lamports().* == 0) return error.InvalidAccountData;
}

// ============================================================================
// Entrypoint
// ============================================================================

export fn entrypoint(input: [*]u8) u64 {
    const context = Context.load(input) catch return 1;
    if (context.data.len == 0) return 1;
    
    const discriminant = context.data[0];
    const accounts = context.accounts[0..context.num_accounts];
    
    switch (discriminant) {
        0 => initializeMint(context.program_id, accounts, context.data) catch return 1,
        1 => initializeAccount(context.program_id, accounts) catch return 1,
        3 => transfer(context.program_id, accounts, context.data) catch return 1,
        7 => mintTo(context.program_id, accounts, context.data) catch return 1,
        8 => burn(context.program_id, accounts, context.data) catch return 1,
        9 => closeAccount(context.program_id, accounts) catch return 1,
        else => return 1,
    }
    
    return 0;
}
