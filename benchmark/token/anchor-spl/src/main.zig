//! SPL Token using anchor-zig's spl.token module
//!
//! Demonstrates Anchor-style account types from anchor.spl.token:
//! - TokenAccount(.{ .mut = true })
//! - MintAccount(.{ .mut = true })
//! - Program
//!
//! This provides type-safe access to token account data.

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const spl = anchor.spl;
const sol = anchor.sdk;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const Rent = sol.rent.Rent;
const AccountState = spl.token.AccountState;
const TokenInstruction = spl.token.TokenInstruction;

// Constants
const NATIVE_MINT_ID = PublicKey.comptimeFromBase58("So11111111111111111111111111111111111111112");
const SYSTEM_PROGRAM_ID = PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// Handlers using spl.token types
// ============================================================================

fn initializeMint(accounts: []Account, data: []const u8) !void {
    if (accounts.len < 2) return error.NotEnoughAccountKeys;
    
    const mint_account = accounts[0];
    const rent_sysvar = accounts[1];

    const mint_data = mint_account.data();
    if (mint_data.len != spl.token.Mint.SIZE) return error.InvalidAccountData;
    
    // Check not already initialized
    if (mint_data[45] == 1) return error.AlreadyInUse;

    // Parse rent using spl.token types
    const rent: *align(1) const Rent.Data = @ptrCast(rent_sysvar.data());
    if (!rent_sysvar.id().equals(Rent.id)) return error.InvalidAccountData;
    if (!rent.isExempt(mint_account.lamports().*, mint_account.dataLen())) return error.NotRentExempt;

    // Parse instruction data
    if (data.len < 35) return error.InvalidInstructionData;
    const decimals = data[1];
    const mint_authority = PublicKey.from(data[2..34].*);
    const has_freeze = data.len >= 67 and data[34] == 1;
    
    // Write mint data
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

fn initializeAccount(program_id: *align(1) PublicKey, accounts: []Account) !void {
    if (accounts.len < 4) return error.NotEnoughAccountKeys;
    
    const token_account = accounts[0];
    const mint_account = accounts[1];
    const owner = accounts[2];
    const rent_sysvar = accounts[3];

    const data = token_account.data();
    if (data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    
    if (data[108] != @intFromEnum(AccountState.Uninitialized)) return error.AlreadyInUse;
    
    const rent: *align(1) const Rent.Data = @ptrCast(rent_sysvar.data());
    if (!rent.isExempt(token_account.lamports().*, token_account.dataLen())) return error.NotRentExempt;

    // Write account data
    @memcpy(data[0..32], &mint_account.id().bytes);
    @memcpy(data[32..64], &owner.id().bytes);
    std.mem.writeInt(u64, data[64..72], 0, .little);
    std.mem.writeInt(u32, data[72..76], 0, .little);
    @memset(data[76..108], 0);
    data[108] = @intFromEnum(AccountState.Initialized);
    
    if (mint_account.id().equals(NATIVE_MINT_ID)) {
        const rent_exempt_reserve = rent.getMinimumBalance(token_account.dataLen());
        std.mem.writeInt(u32, data[109..113], 1, .little);
        std.mem.writeInt(u64, data[113..121], rent_exempt_reserve, .little);
        if (rent_exempt_reserve > token_account.lamports().*) return error.Overflow;
        std.mem.writeInt(u64, data[64..72], token_account.lamports().* - rent_exempt_reserve, .little);
    } else {
        if (!mint_account.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (mint_account.data()[45] != 1) return error.UninitializedState;
        std.mem.writeInt(u32, data[109..113], 0, .little);
        @memset(data[113..121], 0);
    }
    
    std.mem.writeInt(u64, data[121..129], 0, .little);
    std.mem.writeInt(u32, data[129..133], 0, .little);
    @memset(data[133..165], 0);
}

fn transfer(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    // Use spl.token.TokenAccount for type-safe access
    const source = spl.token.TokenAccount(.{ .mut = true }){ .info = accounts[0] };
    const destination = spl.token.TokenAccount(.{ .mut = true }){ .info = accounts[1] };
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    // Use typed accessors
    const source_data = source.info.data();
    const dest_data = destination.info.data();
    
    if (source_data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    if (dest_data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    
    // Check states using typed accessor
    if (source.state() == .Uninitialized) return error.UninitializedState;
    if (destination.state() == .Uninitialized) return error.UninitializedState;
    if (source.isFrozen()) return error.AccountFrozen;
    if (destination.isFrozen()) return error.AccountFrozen;

    // Check balance using typed accessor
    const source_amount = source.amount();
    if (source_amount < amount) return error.InsufficientFunds;
    
    // Check mints match using typed accessor
    if (!source.mint().equals(destination.mint())) return error.MintMismatch;

    // Validate owner
    if (!source.owner().equals(authority.id())) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    // Update amounts
    const pre_amount = source_amount;
    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    std.mem.writeInt(u64, dest_data[64..72], destination.amount() + amount, .little);

    // Handle native token
    if (source.isNative()) {
        source.info.lamports().* -= amount;
        destination.info.lamports().* += amount;
    }

    // Self-transfer check
    if (pre_amount == source_amount) {
        if (!source.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!destination.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn mintTo(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    // Use spl.token types
    const mint = spl.token.MintAccount(.{ .mut = true }){ .info = accounts[0] };
    const destination = spl.token.TokenAccount(.{ .mut = true }){ .info = accounts[1] };
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const mint_data = mint.info.data();
    const dest_data = destination.info.data();
    
    if (mint_data.len != spl.token.Mint.SIZE) return error.InvalidAccountData;
    if (dest_data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    
    // Use typed accessors
    if (!mint.isInitialized()) return error.UninitializedState;
    if (destination.state() == .Uninitialized) return error.UninitializedState;

    if (destination.isNative()) return error.NativeNotSupported;
    if (!mint.key().equals(destination.mint())) return error.MintMismatch;

    // Check mint authority using typed accessor
    const mint_auth = mint.mintAuthority() orelse return error.FixedSupply;
    if (!mint_auth.equals(authority.id())) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    if (amount == 0) {
        if (!mint.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!destination.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }

    // Update supply
    const supply = mint.supply();
    const new_supply = @addWithOverflow(supply, amount);
    if (new_supply[1] != 0) return error.Overflow;
    std.mem.writeInt(u64, mint_data[36..44], new_supply[0], .little);
    
    // Update destination
    std.mem.writeInt(u64, dest_data[64..72], destination.amount() + amount, .little);
}

fn burn(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const source = spl.token.TokenAccount(.{ .mut = true }){ .info = accounts[0] };
    const mint = spl.token.MintAccount(.{ .mut = true }){ .info = accounts[1] };
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const source_data = source.info.data();
    const mint_data = mint.info.data();
    
    if (source_data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    if (mint_data.len != spl.token.Mint.SIZE) return error.InvalidAccountData;
    
    if (source.state() == .Uninitialized) return error.UninitializedState;
    if (!mint.isInitialized()) return error.UninitializedState;

    if (source.isNative()) return error.NativeNotSupported;
    if (!mint.key().equals(source.mint())) return error.MintMismatch;
    
    const source_amount = source.amount();
    if (source_amount < amount) return error.InsufficientFunds;

    if (!source.owner().equals(authority.id())) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    std.mem.writeInt(u64, mint_data[36..44], mint.supply() - amount, .little);

    if (amount == 0) {
        if (!mint.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!source.info.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn closeAccount(program_id: *align(1) PublicKey, accounts: []Account) !void {
    _ = program_id;
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    
    const source = spl.token.TokenAccount(.{ .mut = true }){ .info = accounts[0] };
    const dest_acc = accounts[1];
    const authority = accounts[2];

    const source_data = source.info.data();
    if (source_data.len != spl.token.TokenAccountData.SIZE) return error.InvalidAccountData;
    
    if (source.state() == .Uninitialized) return error.UninitializedState;

    if (!source.isNative() and source.amount() != 0) return error.NonNativeHasBalance;

    // Get authority (close_authority or owner)
    const close_auth_tag = std.mem.readInt(u32, source_data[129..133], .little);
    const expected: *const [32]u8 = if (close_auth_tag == 1)
        source_data[133..165]
    else
        source_data[32..64];

    if (!std.mem.eql(u8, expected, &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    dest_acc.lamports().* += source.info.lamports().*;
    source.info.lamports().* = 0;
    source.info.assign(SYSTEM_PROGRAM_ID);
    source.info.reallocUnchecked(0);

    if (dest_acc.lamports().* == 0) return error.InvalidAccountData;
}

// ============================================================================
// Entrypoint
// ============================================================================

export fn entrypoint(input: [*]u8) u64 {
    var context = sol.context.Context.load(input) catch return 1;
    processInstruction(context.program_id, context.accounts[0..context.num_accounts], context.data) catch return 1;
    return 0;
}

fn processInstruction(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (data.len == 0) return error.InvalidInstruction;
    
    const instruction = TokenInstruction.fromByte(data[0]) orelse return error.InvalidInstruction;
    
    switch (instruction) {
        .InitializeMint => try initializeMint(accounts, data),
        .InitializeAccount => try initializeAccount(program_id, accounts),
        .Transfer => try transfer(program_id, accounts, data),
        .MintTo => try mintTo(program_id, accounts, data),
        .Burn => try burn(program_id, accounts, data),
        .CloseAccount => try closeAccount(program_id, accounts),
        else => return error.InvalidInstruction,
    }
}
