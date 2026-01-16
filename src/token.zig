//! Anchor-style SPL Token helpers and wrappers.
//!
//! Provides TokenAccount/Mint wrappers and CPI helpers mirroring anchor_spl::token.
//!
//! Rust sources:
//! - https://github.com/coral-xyz/anchor/blob/master/spl/src/token.rs
//! - https://github.com/solana-labs/solana-program-library/blob/master/token/program/src/instruction.rs
//! - https://github.com/solana-labs/solana-program-library/blob/master/token/program/src/state.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const account_mod = @import("account.zig");
const associated_token_mod = @import("associated_token.zig");
const init_mod = @import("init.zig");

const AccountInfo = sol.account.Account.Info;
const AccountParam = sol.account.Account.Param;
const AccountMeta = sol.instruction.AccountMeta;
const Instruction = sol.instruction.Instruction;
const PublicKey = sol.PublicKey;
const token_instruction = sol.spl.token.instruction;
const token_state = sol.spl.token.state;
const AssociatedTokenConfig = account_mod.AssociatedTokenConfig;

/// Token program id (SPL Token 1.0).
pub const TOKEN_PROGRAM_ID = sol.spl.TOKEN_PROGRAM_ID;

/// CPI helper errors.
pub const TokenCpiError = union(enum) {
    InvokeFailed,
    InvokeFailedWithCode: u64,
};

/// CPI helper validation errors.
pub const TokenCpiValidationError = error{
    InvalidSignerCount,
};

fn invokeInstruction(
    ix: *const Instruction,
    infos: []const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) ?TokenCpiError {
    const result = if (signer_seeds) |seeds|
        ix.invokeSigned(infos, seeds)
    else
        ix.invoke(infos);
    if (result != null) {
        return .{ .InvokeFailedWithCode = result.?.toU64() };
    }
    return null;
}

fn buildParams(comptime N: usize, metas: *const [N]AccountMeta) [N]AccountParam {
    var params: [N]AccountParam = undefined;
    inline for (metas.*, 0..) |_, i| {
        params[i] = sol.instruction.accountMetaToParam(&metas.*[i]);
    }
    return params;
}

fn resolveKey(comptime field_name: []const u8, accounts: anytype) *const PublicKey {
    const target = @field(accounts, field_name);
    const TargetType = @TypeOf(target);
    if (TargetType == *const AccountInfo) {
        return target.id;
    }
    if (@hasDecl(TargetType, "key")) {
        return target.key();
    }
    if (@typeInfo(TargetType) == .pointer and @hasDecl(@typeInfo(TargetType).pointer.child, "key")) {
        return target.*.key();
    }
    @compileError("constraint target must have key() or be AccountInfo: " ++ field_name);
}

fn resolveAccountInfo(comptime field_name: []const u8, accounts: anytype) *const AccountInfo {
    const target = @field(accounts, field_name);
    const TargetType = @TypeOf(target);
    if (@typeInfo(TargetType) == .pointer) {
        const ChildType = @typeInfo(TargetType).pointer.child;
        if (ChildType == AccountInfo) {
            return target;
        }
        if (@hasDecl(ChildType, "toAccountInfo")) {
            return target.toAccountInfo();
        }
        @compileError("account field must be AccountInfo or type with toAccountInfo(): " ++ field_name);
    }
    if (@hasDecl(TargetType, "toAccountInfo")) {
        return target.toAccountInfo();
    }
    @compileError("account field must be AccountInfo or type with toAccountInfo(): " ++ field_name);
}

fn toAccountInfo(value: anytype) *const AccountInfo {
    const TargetType = @TypeOf(value);
    if (TargetType == AccountInfo) {
        @compileError("AccountInfo values are not supported; pass a pointer");
    }
    if (@typeInfo(TargetType) == .pointer) {
        const ChildType = @typeInfo(TargetType).pointer.child;
        if (ChildType == AccountInfo) {
            return value;
        }
        if (@hasDecl(ChildType, "toAccountInfo")) {
            return value.toAccountInfo();
        }
    }
    if (@hasDecl(TargetType, "toAccountInfo")) {
        return value.toAccountInfo();
    }
    @compileError("value must be AccountInfo pointer or type with toAccountInfo()");
}

fn mintDecimals(value: anytype) u8 {
    const TargetType = @TypeOf(value);
    if (@hasField(TargetType, "data")) {
        return value.data.decimals;
    }
    if (@typeInfo(TargetType) == .pointer) {
        const ChildType = @typeInfo(TargetType).pointer.child;
        if (@hasField(ChildType, "data")) {
            return value.*.data.decimals;
        }
    }
    @compileError("mint account must expose data.decimals");
}

// ============================================================================
// TokenAccount Wrapper
// ============================================================================

/// Token account wrapper configuration.
pub const TokenAccountConfig = struct {
    mut: bool = false,
    signer: bool = false,
    address: ?PublicKey = null,
    token_program: ?[]const u8 = null,
    mint: ?[]const u8 = null,
    authority: ?[]const u8 = null,
    associated: ?AssociatedTokenConfig = null,
    allow_extensions: bool = true,
    init: bool = false,
    init_if_needed: bool = false,
    payer: ?[]const u8 = null,
    system_program: ?[]const u8 = null,
    associated_token_program: ?[]const u8 = null,
};

/// Token account wrapper.
pub fn TokenAccount(comptime config: TokenAccountConfig) type {
    comptime {
        if (config.init or config.init_if_needed) {
            if (config.associated == null) {
                @compileError("TokenAccount init requires associated token config");
            }
            if (config.payer == null) {
                @compileError("TokenAccount init requires payer field name");
            }
            if (config.system_program == null) {
                @compileError("TokenAccount init requires system_program field name");
            }
            if (config.associated_token_program == null) {
                @compileError("TokenAccount init requires associated_token_program field name");
            }
            if (config.token_program == null) {
                @compileError("TokenAccount init requires token_program field name");
            }
        }
    }

    return struct {
        const Self = @This();

        info: *const AccountInfo,
        data: token_state.Account,

        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        /// Load and validate a token account from AccountInfo.
        pub fn load(info: *const AccountInfo) !Self {
            const init_enabled = config.init or config.init_if_needed;
            if (init_enabled and init_mod.isUninitialized(info)) {
                if (config.address) |addr| {
                    if (!info.id.equals(addr)) {
                        return error.ConstraintAddress;
                    }
                }
                if (config.mut and info.is_writable == 0) {
                    return error.ConstraintMut;
                }
                if (config.signer and info.is_signer == 0) {
                    return error.ConstraintSigner;
                }
                return Self{ .info = info, .data = std.mem.zeroes(token_state.Account) };
            }

            if (config.address) |addr| {
                if (!info.id.equals(addr)) {
                    return error.ConstraintAddress;
                }
            }
            if (config.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }
            if (config.signer and info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            if (config.token_program == null and !info.owner_id.equals(TOKEN_PROGRAM_ID)) {
                return error.ConstraintOwner;
            }

            const data = if (config.allow_extensions)
                token_state.Account.unpackUnchecked(info.data[0..info.data_len]) catch {
                    return error.AccountDidNotDeserialize;
                }
            else
                token_state.Account.unpackFromSlice(info.data[0..info.data_len]) catch {
                    return error.AccountDidNotDeserialize;
                };

            return Self{ .info = info, .data = data };
        }

        /// Return the account public key.
        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        /// Return the underlying AccountInfo.
        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }

        /// Validate runtime constraints that depend on other accounts.
        pub fn validateAllConstraints(self: *Self, comptime account_name: []const u8, accounts: anytype) !void {
            _ = account_name;
            const associated_token_program_id = comptime PublicKey.comptimeFromBase58(
                "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
            );

            const default_token_program = TOKEN_PROGRAM_ID;
            const token_program_key = if (config.token_program) |field_name|
                resolveKey(field_name, accounts).*
            else
                default_token_program;

            const init_enabled = config.init or config.init_if_needed;
            if (init_enabled) {
                const uninitialized = init_mod.isUninitialized(self.info);
                if (!uninitialized and !config.init_if_needed) {
                    return error.ConstraintAssociatedInit;
                }
                if (uninitialized) {
                    if (self.info.is_writable == 0) {
                        return error.ConstraintAssociatedInit;
                    }
                    const payer_info = resolveAccountInfo(config.payer.?, accounts);
                    if (payer_info.is_signer == 0 or payer_info.is_writable == 0) {
                        return error.ConstraintAssociatedInit;
                    }
                    const system_program_info = resolveAccountInfo(config.system_program.?, accounts);
                    const associated_token_program_info = resolveAccountInfo(config.associated_token_program.?, accounts);
                    const token_program_info = resolveAccountInfo(config.token_program.?, accounts);

                    const cpi_err = if (config.init_if_needed)
                        associated_token_mod.createIdempotent(
                            associated_token_program_info,
                            payer_info,
                            self.info,
                            resolveAccountInfo(config.associated.?.authority, accounts),
                            resolveAccountInfo(config.associated.?.mint, accounts),
                            system_program_info,
                            token_program_info,
                            null,
                        )
                    else
                        associated_token_mod.create(
                            associated_token_program_info,
                            payer_info,
                            self.info,
                            resolveAccountInfo(config.associated.?.authority, accounts),
                            resolveAccountInfo(config.associated.?.mint, accounts),
                            system_program_info,
                            token_program_info,
                            null,
                        );
                    if (cpi_err != null) {
                        return error.ConstraintAssociatedInit;
                    }
                }
            }

            if (!self.info.owner_id.equals(token_program_key)) {
                return error.ConstraintOwner;
            }

            const token_account = if (config.allow_extensions)
                token_state.Account.unpackUnchecked(self.info.data[0..self.info.data_len]) catch {
                    return error.ConstraintTokenOwner;
                }
            else
                token_state.Account.unpackFromSlice(self.info.data[0..self.info.data_len]) catch {
                    return error.ConstraintTokenOwner;
                };
            self.data = token_account;

            if (config.mint) |field_name| {
                const mint_key = resolveKey(field_name, accounts).*;
                if (!token_account.mint.equals(mint_key)) {
                    return error.ConstraintTokenMint;
                }
            }

            if (config.authority) |field_name| {
                const owner_key = resolveKey(field_name, accounts).*;
                if (!token_account.owner.equals(owner_key)) {
                    return error.ConstraintTokenOwner;
                }
            }

            if (config.associated) |cfg| {
                const authority_key = resolveKey(cfg.authority, accounts).*;
                const mint_key = resolveKey(cfg.mint, accounts).*;
                const token_program_key_associated = if (cfg.token_program) |field_name|
                    resolveKey(field_name, accounts).*
                else
                    default_token_program;

                if (!self.info.owner_id.equals(token_program_key_associated)) {
                    return error.ConstraintOwner;
                }
                if (!token_account.owner.equals(authority_key)) {
                    return error.ConstraintTokenOwner;
                }
                if (!token_account.mint.equals(mint_key)) {
                    return error.ConstraintAssociated;
                }

                const seeds = .{ &authority_key.bytes, &token_program_key_associated.bytes, &mint_key.bytes };
                const derived = PublicKey.findProgramAddress(seeds, associated_token_program_id) catch {
                    return error.ConstraintAssociated;
                };
                if (!self.info.id.equals(derived.address)) {
                    return error.ConstraintAssociated;
                }
            }
        }
    };
}

// ============================================================================
// Mint Wrapper
// ============================================================================

/// Mint account wrapper configuration.
pub const MintConfig = struct {
    mut: bool = false,
    signer: bool = false,
    address: ?PublicKey = null,
    token_program: ?[]const u8 = null,
    authority: ?[]const u8 = null,
    freeze_authority: ?[]const u8 = null,
    decimals: ?u8 = null,
    allow_extensions: bool = true,
};

/// Mint account wrapper.
pub fn Mint(comptime config: MintConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,
        data: token_state.Mint,

        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        /// Load and validate a mint account from AccountInfo.
        pub fn load(info: *const AccountInfo) !Self {
            if (config.address) |addr| {
                if (!info.id.equals(addr)) {
                    return error.ConstraintAddress;
                }
            }
            if (config.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }
            if (config.signer and info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            if (config.token_program == null and !info.owner_id.equals(TOKEN_PROGRAM_ID)) {
                return error.ConstraintOwner;
            }

            const data = if (config.allow_extensions)
                token_state.Mint.unpackUnchecked(info.data[0..info.data_len]) catch {
                    return error.AccountDidNotDeserialize;
                }
            else
                token_state.Mint.unpackFromSlice(info.data[0..info.data_len]) catch {
                    return error.AccountDidNotDeserialize;
                };

            return Self{ .info = info, .data = data };
        }

        /// Return the mint public key.
        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        /// Return the underlying AccountInfo.
        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }

        /// Validate runtime constraints that depend on other accounts.
        pub fn validateAllConstraints(self: Self, comptime account_name: []const u8, accounts: anytype) !void {
            _ = account_name;
            const default_token_program = TOKEN_PROGRAM_ID;
            const token_program_key = if (config.token_program) |field_name|
                resolveKey(field_name, accounts).*
            else
                default_token_program;

            if (!self.info.owner_id.equals(token_program_key)) {
                return error.ConstraintOwner;
            }

            if (config.authority) |field_name| {
                const authority_key = resolveKey(field_name, accounts).*;
                if (!self.data.mint_authority.isSome() or
                    !self.data.mint_authority.unwrap().equals(authority_key))
                {
                    return error.ConstraintMintMintAuthority;
                }
            }

            if (config.freeze_authority) |field_name| {
                const authority_key = resolveKey(field_name, accounts).*;
                if (!self.data.freeze_authority.isSome() or
                    !self.data.freeze_authority.unwrap().equals(authority_key))
                {
                    return error.ConstraintMintFreezeAuthority;
                }
            }

            if (config.decimals) |decimals| {
                if (self.data.decimals != decimals) {
                    return error.ConstraintMintDecimals;
                }
            }
        }
    };
}

// ============================================================================
// Token CPI helpers
// ============================================================================

/// Invoke SPL Token transfer.
pub fn transfer(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
) ?TokenCpiError {
    const built = token_instruction.transfer(source.id.*, destination.id.*, authority.id.*, amount);
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token transfer with signer seeds.
pub fn transferSigned(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
    signer_seeds: []const []const []const u8,
) ?TokenCpiError {
    const built = token_instruction.transfer(source.id.*, destination.id.*, authority.id.*, amount);
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke SPL Token transfer for multisig authority.
pub fn transferMultisig(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    destination: *const AccountInfo,
    owner: *const AccountInfo,
    signer_infos: []const *const AccountInfo,
    amount: u64,
) TokenCpiValidationError!?TokenCpiError {
    if (signer_infos.len == 0 or signer_infos.len > token_instruction.MAX_SIGNERS) {
        return TokenCpiValidationError.InvalidSignerCount;
    }

    const signers = blk: {
        var list: [token_instruction.MAX_SIGNERS]PublicKey = undefined;
        for (signer_infos, 0..) |signer, i| {
            list[i] = signer.id.*;
        }
        break :blk list[0..signer_infos.len];
    };

    const built = token_instruction.transferMultisig(
        source.id.*,
        destination.id.*,
        owner.id.*,
        signers,
        amount,
    ) catch {
        return TokenCpiValidationError.InvalidSignerCount;
    };

    var metas = built.accounts;
    var params: [token_instruction.MAX_SIGNERS + 3]AccountParam = undefined;
    for (metas[0..built.num_accounts], 0..) |_, i| {
        params[i] = sol.instruction.accountMetaToParam(&metas[i]);
    }
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..built.num_accounts],
        .data = built.data[0..],
    });

    var infos: [token_instruction.MAX_SIGNERS + 3]AccountInfo = undefined;
    infos[0] = source.*;
    infos[1] = destination.*;
    infos[2] = owner.*;
    for (signer_infos, 0..) |signer, i| {
        infos[3 + i] = signer.*;
    }

    return invokeInstruction(&ix, infos[0 .. 3 + signer_infos.len], null);
}

/// Invoke SPL Token transferChecked.
pub fn transferChecked(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    mint: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
    decimals: u8,
) ?TokenCpiError {
    const built = token_instruction.transferChecked(
        source.id.*,
        mint.id.*,
        destination.id.*,
        authority.id.*,
        amount,
        decimals,
    );
    var metas = built.accounts;
    const params = buildParams(4, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source.*, mint.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token transferChecked using mint wrapper decimals.
pub fn transferCheckedWithMint(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    mint_account: anytype,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
) ?TokenCpiError {
    const mint_info = toAccountInfo(mint_account);
    const decimals = mintDecimals(mint_account);
    return transferChecked(
        token_program,
        source,
        mint_info,
        destination,
        authority,
        amount,
        decimals,
    );
}

/// Invoke SPL Token mintTo.
pub fn mintTo(
    token_program: *const AccountInfo,
    mint: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
) ?TokenCpiError {
    const built = token_instruction.mintTo(
        mint.id.*,
        destination.id.*,
        authority.id.*,
        amount,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ mint.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token mintToChecked.
pub fn mintToChecked(
    token_program: *const AccountInfo,
    mint: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
    decimals: u8,
) ?TokenCpiError {
    const built = token_instruction.mintToChecked(
        mint.id.*,
        destination.id.*,
        authority.id.*,
        amount,
        decimals,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ mint.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token burn.
pub fn burn(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
    mint: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
) ?TokenCpiError {
    const built = token_instruction.burn(
        account.id.*,
        mint.id.*,
        authority.id.*,
        amount,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.*, mint.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token burnChecked.
pub fn burnChecked(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
    mint: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
    decimals: u8,
) ?TokenCpiError {
    const built = token_instruction.burnChecked(
        account.id.*,
        mint.id.*,
        authority.id.*,
        amount,
        decimals,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.*, mint.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token approve.
pub fn approve(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    delegate: *const AccountInfo,
    authority: *const AccountInfo,
    amount: u64,
) ?TokenCpiError {
    const built = token_instruction.approve(
        source.id.*,
        delegate.id.*,
        authority.id.*,
        amount,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source.*, delegate.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token revoke.
pub fn revoke(
    token_program: *const AccountInfo,
    source: *const AccountInfo,
    authority: *const AccountInfo,
) ?TokenCpiError {
    const built = token_instruction.revoke(source.id.*, authority.id.*);
    var metas = built.accounts;
    const params = buildParams(2, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token closeAccount.
pub fn closeAccount(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
    destination: *const AccountInfo,
    authority: *const AccountInfo,
) ?TokenCpiError {
    const built = token_instruction.closeAccount(
        account.id.*,
        destination.id.*,
        authority.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.*, destination.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token freezeAccount.
pub fn freezeAccount(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
    mint: *const AccountInfo,
    authority: *const AccountInfo,
) ?TokenCpiError {
    const built = token_instruction.freezeAccount(account.id.*, mint.id.*, authority.id.*);
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.*, mint.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token thawAccount.
pub fn thawAccount(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
    mint: *const AccountInfo,
    authority: *const AccountInfo,
) ?TokenCpiError {
    const built = token_instruction.thawAccount(account.id.*, mint.id.*, authority.id.*);
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.*, mint.*, authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token setAuthority.
pub fn setAuthority(
    token_program: *const AccountInfo,
    account_or_mint: *const AccountInfo,
    current_authority: *const AccountInfo,
    authority_type: token_instruction.AuthorityType,
    new_authority: ?PublicKey,
) ?TokenCpiError {
    const built = token_instruction.setAuthority(
        account_or_mint.id.*,
        current_authority.id.*,
        authority_type,
        new_authority,
    );
    var metas = built.accounts;
    const params = buildParams(2, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..built.data_len],
    });
    const infos = [_]AccountInfo{ account_or_mint.*, current_authority.* };
    return invokeInstruction(&ix, infos[0..], null);
}

/// Invoke SPL Token syncNative for wrapped SOL.
pub fn syncNative(
    token_program: *const AccountInfo,
    account: *const AccountInfo,
) ?TokenCpiError {
    const built = token_instruction.syncNative(account.id.*);
    var metas = built.accounts;
    const params = buildParams(1, &metas);
    const ix = Instruction.from(.{
        .program_id = token_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ account.* };
    return invokeInstruction(&ix, infos[0..], null);
}

// ============================================================================
// Tests
// ============================================================================

test "TokenAccount load parses data" {
    const token_program = TOKEN_PROGRAM_ID;
    var owner = token_program;
    var account_id = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [token_state.Account.SIZE]u8 = undefined;
    @memset(&buffer, 0);

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const Wrapper = TokenAccount(.{});
    _ = try Wrapper.load(&info);
}

test "TokenAccount load allows uninitialized init" {
    var owner = sol.system_program.id;
    var account_id = PublicKey.default();
    var lamports: u64 = 0;
    var data: [0]u8 = undefined;

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const Wrapper = TokenAccount(.{
        .associated = .{ .mint = "mint", .authority = "authority" },
        .init = true,
        .payer = "payer",
        .system_program = "system_program",
        .associated_token_program = "associated_token_program",
        .token_program = "token_program",
    });
    _ = try Wrapper.load(&info);
}

test "Mint load parses data" {
    const token_program = TOKEN_PROGRAM_ID;
    var owner = token_program;
    var mint_id = PublicKey.default();
    var lamports: u64 = 1;
    var buffer: [token_state.Mint.SIZE]u8 = undefined;
    @memset(&buffer, 0);

    const info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
        .rent_epoch = 0,
    };

    const Wrapper = Mint(.{});
    _ = try Wrapper.load(&info);
}
