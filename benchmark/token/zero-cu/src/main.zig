//! SPL Token implemented with anchor-zig SDK types
//!
//! Uses SDK's SPL Token types (sdk.spl.token) for type-safe
//! account parsing and instruction handling.
//!
//! This demonstrates how to use the SDK's built-in SPL Token
//! support for implementing token programs.

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// Import SPL Token types from SDK
const spl_token = sol.spl.token;
const Mint = spl_token.Mint;
const TokenAccount = spl_token.Account;
const AccountState = spl_token.AccountState;
const TokenInstruction = spl_token.TokenInstruction;
const COption = spl_token.COption;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const Rent = sol.rent.Rent;

// Program IDs
const NATIVE_MINT_ID = PublicKey.comptimeFromBase58("So11111111111111111111111111111111111111112");
const SYSTEM_PROGRAM_ID = PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// Handlers
// ============================================================================

fn initializeMint(accounts: []Account, data: []const u8) !void {
    if (accounts.len < 2) return error.NotEnoughAccountKeys;
    
    const mint_account = accounts[0];
    const rent_sysvar = accounts[1];

    const mint_data = mint_account.data();
    if (mint_data.len != Mint.SIZE) return error.InvalidAccountData;
    
    // Check not already initialized (is_initialized at offset 45)
    if (mint_data[45] == 1) return error.AlreadyInUse;

    // Parse rent
    const rent: *align(1) const Rent.Data = @ptrCast(rent_sysvar.data());
    if (!rent_sysvar.id().equals(Rent.id)) return error.InvalidAccountData;
    if (!rent.isExempt(mint_account.lamports().*, mint_account.dataLen())) return error.NotRentExempt;

    // Parse instruction data (offset 1 for decimals, 2-34 for mint_authority, 34 for freeze_authority option)
    if (data.len < 35) return error.InvalidInstructionData;
    const decimals = data[1];
    const mint_authority = PublicKey.from(data[2..34].*);
    const has_freeze = data.len >= 67 and data[34] == 1;
    
    // Write mint data
    std.mem.writeInt(u32, mint_data[0..4], 1, .little); // mint_authority = Some
    @memcpy(mint_data[4..36], &mint_authority.bytes);
    std.mem.writeInt(u64, mint_data[36..44], 0, .little); // supply = 0
    mint_data[44] = decimals;
    mint_data[45] = 1; // is_initialized = true
    
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
    if (data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    
    // Check state is uninitialized (offset 108)
    if (data[108] != @intFromEnum(AccountState.Uninitialized)) return error.AlreadyInUse;
    
    const rent: *align(1) const Rent.Data = @ptrCast(rent_sysvar.data());
    if (!rent.isExempt(token_account.lamports().*, token_account.dataLen())) return error.NotRentExempt;

    // Write account data
    @memcpy(data[0..32], &mint_account.id().bytes);   // mint
    @memcpy(data[32..64], &owner.id().bytes);         // owner
    std.mem.writeInt(u64, data[64..72], 0, .little);  // amount = 0
    std.mem.writeInt(u32, data[72..76], 0, .little);  // delegate = None
    @memset(data[76..108], 0);
    data[108] = @intFromEnum(AccountState.Initialized);
    
    // Handle native mint
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
    
    const source_acc = accounts[0];
    const dest_acc = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const source_data = source_acc.data();
    const dest_data = dest_acc.data();
    
    if (source_data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    if (dest_data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    
    // Check states
    if (source_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (dest_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (source_data[108] == @intFromEnum(AccountState.Frozen)) return error.AccountFrozen;
    if (dest_data[108] == @intFromEnum(AccountState.Frozen)) return error.AccountFrozen;

    // Check balance
    const source_amount = std.mem.readInt(u64, source_data[64..72], .little);
    if (source_amount < amount) return error.InsufficientFunds;
    
    // Check mints match
    if (!std.mem.eql(u8, source_data[0..32], dest_data[0..32])) return error.MintMismatch;

    // Validate owner
    if (!std.mem.eql(u8, source_data[32..64], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    // Update amounts
    const pre_amount = source_amount;
    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    const dest_amount = std.mem.readInt(u64, dest_data[64..72], .little);
    std.mem.writeInt(u64, dest_data[64..72], dest_amount + amount, .little);

    // Handle native token
    if (std.mem.readInt(u32, source_data[109..113], .little) == 1) {
        source_acc.lamports().* -= amount;
        dest_acc.lamports().* += amount;
    }

    // Self-transfer check
    if (pre_amount == source_amount) {
        if (!source_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!dest_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn mintTo(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const mint_acc = accounts[0];
    const dest_acc = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const mint_data = mint_acc.data();
    const dest_data = dest_acc.data();
    
    if (mint_data.len != Mint.SIZE) return error.InvalidAccountData;
    if (dest_data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    
    // Check initialized
    if (mint_data[45] != 1) return error.UninitializedState;
    if (dest_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;

    // Check native
    if (std.mem.readInt(u32, dest_data[109..113], .little) == 1) return error.NativeNotSupported;
    
    // Check mint matches
    if (!std.mem.eql(u8, &mint_acc.id().bytes, dest_data[0..32])) return error.MintMismatch;

    // Check mint authority
    if (std.mem.readInt(u32, mint_data[0..4], .little) == 0) return error.FixedSupply;
    if (!std.mem.eql(u8, mint_data[4..36], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    // Zero amount check
    if (amount == 0) {
        if (!mint_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!dest_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }

    // Update supply
    const supply = std.mem.readInt(u64, mint_data[36..44], .little);
    const new_supply = @addWithOverflow(supply, amount);
    if (new_supply[1] != 0) return error.Overflow;
    std.mem.writeInt(u64, mint_data[36..44], new_supply[0], .little);
    
    // Update destination
    const dest_amount = std.mem.readInt(u64, dest_data[64..72], .little);
    std.mem.writeInt(u64, dest_data[64..72], dest_amount + amount, .little);
}

fn burn(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) !void {
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    if (data.len < 9) return error.InvalidInstructionData;
    
    const source_acc = accounts[0];
    const mint_acc = accounts[1];
    const authority = accounts[2];
    
    const amount = std.mem.readInt(u64, data[1..9], .little);

    const source_data = source_acc.data();
    const mint_data = mint_acc.data();
    
    if (source_data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    if (mint_data.len != Mint.SIZE) return error.InvalidAccountData;
    
    // Check states
    if (source_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;
    if (mint_data[45] != 1) return error.UninitializedState;

    // Check native
    if (std.mem.readInt(u32, source_data[109..113], .little) == 1) return error.NativeNotSupported;
    
    // Check mint matches
    if (!std.mem.eql(u8, &mint_acc.id().bytes, source_data[0..32])) return error.MintMismatch;
    
    // Check balance
    const source_amount = std.mem.readInt(u64, source_data[64..72], .little);
    if (source_amount < amount) return error.InsufficientFunds;

    // Validate owner
    if (!std.mem.eql(u8, source_data[32..64], &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    // Update amounts
    std.mem.writeInt(u64, source_data[64..72], source_amount - amount, .little);
    const supply = std.mem.readInt(u64, mint_data[36..44], .little);
    std.mem.writeInt(u64, mint_data[36..44], supply - amount, .little);

    // Zero amount check
    if (amount == 0) {
        if (!mint_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
        if (!source_acc.ownerId().equals(program_id.*)) return error.IllegalOwner;
    }
}

fn closeAccount(program_id: *align(1) PublicKey, accounts: []Account) !void {
    _ = program_id;
    if (accounts.len < 3) return error.NotEnoughAccountKeys;
    
    const source_acc = accounts[0];
    const dest_acc = accounts[1];
    const authority = accounts[2];

    const source_data = source_acc.data();
    if (source_data.len != TokenAccount.SIZE) return error.InvalidAccountData;
    
    // Check state
    if (source_data[108] == @intFromEnum(AccountState.Uninitialized)) return error.UninitializedState;

    // Check balance for non-native
    const is_native = std.mem.readInt(u32, source_data[109..113], .little) == 1;
    const source_amount = std.mem.readInt(u64, source_data[64..72], .little);
    if (!is_native and source_amount != 0) return error.NonNativeHasBalance;

    // Get authority
    const close_auth_tag = std.mem.readInt(u32, source_data[129..133], .little);
    const expected: *const [32]u8 = if (close_auth_tag == 1)
        source_data[133..165]
    else
        source_data[32..64];

    if (!std.mem.eql(u8, expected, &authority.id().bytes)) return error.OwnerMismatch;
    if (!authority.isSigner()) return error.MissingRequiredSignature;

    // Transfer and close
    dest_acc.lamports().* += source_acc.lamports().*;
    source_acc.lamports().* = 0;
    source_acc.assign(SYSTEM_PROGRAM_ID);
    source_acc.reallocUnchecked(0);

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
