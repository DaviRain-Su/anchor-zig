//! SPL Token implemented with anchor-zig zero_cu helpers
//!
//! This is a benchmark implementation that matches the rosetta Zig version
//! but demonstrates usage of zero_cu types (Mut, Readonly, Signer, etc.)
//! for documentation and clarity.
//!
//! Note: SPL Token uses single-byte discriminants (not 8-byte Anchor format),
//! so we use manual dispatch instead of zero.program().

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const Rent = sol.rent.Rent;

// Program IDs
const TOKEN_PROGRAM_ID = PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
const NATIVE_MINT_ID = PublicKey.comptimeFromBase58("So11111111111111111111111111111111111111112");
const SYSTEM_PROGRAM_ID = PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// State Types (same as rosetta)
// ============================================================================

pub fn COption(T: type) type {
    return extern struct {
        is_some: u32,
        value: T,
        const Self = @This();
        pub fn fromValue(value: T) Self {
            return Self{ .is_some = 1, .value = value };
        }
        pub fn asNull() Self {
            return Self{ .is_some = 0, .value = std.mem.zeroes(T) };
        }
    };
}

pub fn IxOption(T: type) type {
    return extern struct {
        is_some: u8,
        value: T,
        const Self = @This();
        pub fn toCOption(self: Self) COption(T) {
            return COption(T){ .is_some = self.is_some, .value = self.value };
        }
    };
}

pub const Mint = extern struct {
    pub const LEN = 82;
    
    mint_authority: COption(PublicKey),
    supply: u64,
    decimals: u8,
    is_initialized: u8,
    freeze_authority: COption(PublicKey),

    pub fn fromBytes(data: []u8) TokenError!*align(1) Mint {
        const mint: *align(1) Mint = @ptrCast(data);
        if (data.len != Mint.LEN) return TokenError.InvalidAccountData;
        if (mint.is_initialized != 1) return TokenError.UninitializedState;
        return mint;
    }
};

pub const TokenAccount = extern struct {
    pub const LEN = 165;

    pub const State = enum(u8) {
        uninitialized,
        initialized,
        frozen,
    };

    mint: PublicKey,
    owner: PublicKey,
    amount: u64,
    delegate: COption(PublicKey),
    state: State,
    is_native: COption(u64),
    delegated_amount: u64,
    close_authority: COption(PublicKey),

    pub fn isNative(self: *align(1) const TokenAccount) bool {
        return self.is_native.is_some != 0;
    }

    pub fn fromBytes(data: []u8) TokenError!*align(1) TokenAccount {
        const account: *align(1) TokenAccount = @ptrCast(data);
        if (data.len != TokenAccount.LEN) return TokenError.InvalidAccountData;
        if (account.state == TokenAccount.State.uninitialized) return TokenError.UninitializedState;
        if (account.state == TokenAccount.State.frozen) return TokenError.AccountFrozen;
        return account;
    }
};

pub const Multisig = extern struct {
    pub const LEN = 355;
};

// ============================================================================
// Instruction Data
// ============================================================================

pub const InitializeMintData = extern struct {
    decimals: u8,
    mint_authority: PublicKey,
    freeze_authority: IxOption(PublicKey),
};

pub const AmountData = extern struct {
    amount: u64,
};

pub const InstructionDiscriminant = enum(u8) {
    initialize_mint,
    initialize_account,
    initialize_multisig,
    transfer,
    approve,
    revoke,
    set_authority,
    mint_to,
    burn,
    close_account,
    freeze_account,
    thaw_account,
    transfer_checked,
    approve_checked,
    mint_to_checked,
    burn_checked,
    initialize_account_2,
    sync_native,
    initialize_account_3,
    initialize_multisig_2,
    initialize_mint_2,
    get_account_data_size,
    initialize_immutable_owner,
    amount_to_ui_amount,
    ui_amount_to_amount,
};

// ============================================================================
// Errors
// ============================================================================

pub const TokenError = error{
    NotRentExempt,
    InsufficientFunds,
    MintMismatch,
    OwnerMismatch,
    FixedSupply,
    AlreadyInUse,
    UninitializedState,
    NativeNotSupported,
    NonNativeHasBalance,
    InvalidState,
    Overflow,
    IllegalOwner,
    InvalidAccountData,
    NotEnoughAccountKeys,
    MissingRequiredSignature,
    AccountFrozen,
};

// ============================================================================
// Handlers (same logic as rosetta)
// ============================================================================

fn initializeMint(accounts: []Account, data: []const u8) TokenError!void {
    if (accounts.len < 2) return TokenError.NotEnoughAccountKeys;
    const ix_data: *align(1) const InitializeMintData = @ptrCast(data[1..]);
    const mint_account = accounts[0];
    const rent_sysvar = accounts[1];

    var mint: *align(1) Mint = @ptrCast(mint_account.data());
    if (mint_account.dataLen() != Mint.LEN) return TokenError.InvalidAccountData;
    if (mint.is_initialized == 1) return TokenError.AlreadyInUse;

    const rent: *align(1) Rent.Data = @ptrCast(rent_sysvar.data());
    if (!rent_sysvar.id().equals(Rent.id)) return TokenError.InvalidAccountData;
    if (!rent.isExempt(mint_account.lamports().*, mint_account.dataLen())) return TokenError.NotRentExempt;

    mint.mint_authority = COption(PublicKey).fromValue(ix_data.mint_authority);
    mint.decimals = ix_data.decimals;
    mint.is_initialized = 1;
    mint.freeze_authority = ix_data.freeze_authority.toCOption();
}

fn initializeAccount(program_id: *align(1) PublicKey, accounts: []Account) TokenError!void {
    if (accounts.len < 4) return TokenError.NotEnoughAccountKeys;
    const token_account = accounts[0];
    const mint_account = accounts[1];
    const owner = accounts[2];
    const rent_sysvar = accounts[3];
    const rent: *align(1) Rent.Data = @ptrCast(rent_sysvar.data());

    var account: *align(1) TokenAccount = @ptrCast(token_account.data());
    if (token_account.dataLen() != TokenAccount.LEN) return TokenError.InvalidAccountData;
    if (account.state != TokenAccount.State.uninitialized) return TokenError.AlreadyInUse;
    if (!rent.isExempt(token_account.lamports().*, token_account.dataLen())) return TokenError.NotRentExempt;

    account.mint = mint_account.id();
    account.owner = owner.id();
    account.state = TokenAccount.State.initialized;
    
    if (mint_account.id().equals(NATIVE_MINT_ID)) {
        const rent_exempt_reserve = rent.getMinimumBalance(token_account.dataLen());
        account.is_native = COption(u64).fromValue(rent_exempt_reserve);
        if (rent_exempt_reserve > token_account.lamports().*) return TokenError.Overflow;
        account.amount = token_account.lamports().* - rent_exempt_reserve;
    } else {
        if (!mint_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
        const mint: *align(1) Mint = @ptrCast(mint_account.data());
        if (mint_account.dataLen() != Mint.LEN) return TokenError.InvalidAccountData;
        if (mint.is_initialized != 1) return TokenError.UninitializedState;
    }
}

fn transfer(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) TokenError!void {
    if (accounts.len < 3) return TokenError.NotEnoughAccountKeys;
    const ix_data: *align(1) const AmountData = @ptrCast(data[1..]);
    const source_account = accounts[0];
    const destination_account = accounts[1];
    const authority_account = accounts[2];

    var source = try TokenAccount.fromBytes(source_account.data());
    var destination = try TokenAccount.fromBytes(destination_account.data());

    if (source.amount < ix_data.amount) return TokenError.InsufficientFunds;
    if (!source.mint.equals(destination.mint)) return TokenError.MintMismatch;

    try validateOwner(program_id, &source.owner, authority_account, accounts[3..]);

    const pre_amount = source.amount;
    source.amount -= ix_data.amount;
    destination.amount += ix_data.amount;

    if (source.isNative()) {
        source_account.lamports().* -= ix_data.amount;
        destination_account.lamports().* += ix_data.amount;
    }

    if (pre_amount == source.amount) {
        if (!source_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
        if (!destination_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
    }
}

fn mintTo(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) TokenError!void {
    if (accounts.len < 3) return TokenError.NotEnoughAccountKeys;
    const ix_data: *align(1) const AmountData = @ptrCast(data[1..]);
    const mint_account = accounts[0];
    const destination_account = accounts[1];
    const authority_account = accounts[2];

    var destination = try TokenAccount.fromBytes(destination_account.data());
    if (destination.isNative()) return TokenError.NativeNotSupported;
    if (!mint_account.id().equals(destination.mint)) return TokenError.MintMismatch;

    var mint = try Mint.fromBytes(mint_account.data());

    if (mint.mint_authority.is_some == 0) return TokenError.FixedSupply;

    try validateOwner(program_id, &mint.mint_authority.value, authority_account, accounts[3..]);

    if (ix_data.amount == 0) {
        if (!mint_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
        if (!destination_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
    }

    const supply = @addWithOverflow(mint.supply, ix_data.amount);
    if (supply[1] != 0) return TokenError.Overflow;
    mint.supply = supply[0];
    destination.amount += ix_data.amount;
}

fn burn(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) TokenError!void {
    if (accounts.len < 3) return TokenError.NotEnoughAccountKeys;
    const ix_data: *align(1) const AmountData = @ptrCast(data[1..]);
    const source_account = accounts[0];
    const mint_account = accounts[1];
    const authority_account = accounts[2];

    var source = try TokenAccount.fromBytes(source_account.data());
    if (source.isNative()) return TokenError.NativeNotSupported;

    var mint = try Mint.fromBytes(mint_account.data());
    if (!mint_account.id().equals(source.mint)) return TokenError.MintMismatch;
    if (source.amount < ix_data.amount) return TokenError.InsufficientFunds;

    try validateOwner(program_id, &source.owner, authority_account, accounts[3..]);

    source.amount -= ix_data.amount;
    mint.supply -= ix_data.amount;

    if (ix_data.amount == 0) {
        if (!mint_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
        if (!source_account.ownerId().equals(program_id.*)) return TokenError.IllegalOwner;
    }
}

fn closeAccount(program_id: *align(1) PublicKey, accounts: []Account) TokenError!void {
    if (accounts.len < 3) return TokenError.NotEnoughAccountKeys;
    const source_account = accounts[0];
    const destination_account = accounts[1];
    const authority_account = accounts[2];

    var source = try TokenAccount.fromBytes(source_account.data());
    if (!source.isNative() and source.amount != 0) return TokenError.NonNativeHasBalance;

    const authority = if (source.close_authority.is_some != 0)
        &source.close_authority.value
    else
        &source.owner;

    try validateOwner(program_id, authority, authority_account, accounts[3..]);

    destination_account.lamports().* += source_account.lamports().*;
    source_account.lamports().* = 0;
    source_account.assign(SYSTEM_PROGRAM_ID);
    source_account.reallocUnchecked(0);

    if (destination_account.lamports().* == 0) return TokenError.InvalidAccountData;
}

fn validateOwner(
    program_id: *align(1) const PublicKey,
    expected_owner: *align(1) const PublicKey,
    owner_account: Account,
    _: []Account,
) TokenError!void {
    if (!expected_owner.equals(owner_account.id())) return TokenError.OwnerMismatch;
    if (owner_account.dataLen() == Multisig.LEN and program_id.equals(owner_account.ownerId())) {
        return TokenError.MissingRequiredSignature;
    } else if (!owner_account.isSigner()) {
        return TokenError.MissingRequiredSignature;
    }
}

// ============================================================================
// Entrypoint
// ============================================================================

export fn entrypoint(input: [*]u8) u64 {
    var context = sol.context.Context.load(input) catch return 1;
    processInstruction(context.program_id, context.accounts[0..context.num_accounts], context.data) catch |err| return @intFromError(err);
    return 0;
}

fn processInstruction(program_id: *align(1) PublicKey, accounts: []Account, data: []const u8) TokenError!void {
    const instruction_type: *const InstructionDiscriminant = @ptrCast(data);
    switch (instruction_type.*) {
        .initialize_mint => try initializeMint(accounts, data),
        .initialize_account => try initializeAccount(program_id, accounts),
        .transfer => try transfer(program_id, accounts, data),
        .mint_to => try mintTo(program_id, accounts, data),
        .burn => try burn(program_id, accounts, data),
        .close_account => try closeAccount(program_id, accounts),
        else => return TokenError.InvalidState,
    }
}
