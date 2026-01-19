//! Optimized Anchor Entry Point
//!
//! This module provides optimized entry point generators that combine
//! Anchor's high-level API with ZeroCU's performance optimizations.
//!
//! ## API Levels
//!
//! | API                  | CU    | Features                        |
//! |----------------------|-------|----------------------------------|
//! | `exportZero`         | 5-7   | ZeroCU backend, Anchor Context   |
//! | `exportEntrypoint`   | 31+   | Full SDK parsing                 |

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");
const context_mod = @import("context.zig");
const zero_cu = @import("zero_cu.zig");

const PublicKey = sol.PublicKey;
const AccountInfo = sol.account.Account.Info;

/// Validation level for accounts
pub const ValidationLevel = enum {
    /// Full validation: discriminator, owner, signer, address, mut
    full,
    /// Minimal validation: discriminator + signer only
    minimal,
    /// Unchecked: discriminator only (fastest, use with caution)
    unchecked,
};

// ============================================================================
// Zero-Overhead Export (5-7 CU)
// ============================================================================

/// Export zero-overhead entrypoint with Anchor-style Context
///
/// This combines ZeroCU's comptime offset calculation with Anchor's Context API.
/// Achieves 5-7 CU like ZeroCU but with familiar Anchor patterns.
///
/// ## Requirements
/// - All account types must specify data size via `zero.Signer(size)`, etc.
/// - Single instruction only (use `exportZeroMulti` for multiple)
///
/// ## Example
/// ```zig
/// const zero = anchor.zero_cu;
///
/// const MyAccounts = struct {
///     authority: zero.Signer(0),
///     target: zero.Readonly(1),
/// };
///
/// pub const Program = struct {
///     pub const id = sol.PublicKey.comptimeFromBase58("...");
///
///     pub const instructions = struct {
///         pub const check = anchor.Instruction(.{ .Accounts = MyAccounts });
///     };
///
///     pub fn check(ctx: anchor.Context(MyAccounts)) !void {
///         // Use standard Anchor Context API
///         _ = ctx.accounts.authority;
///     }
/// };
///
/// comptime {
///     anchor.optimized.exportZero(Program, "check");
/// }
/// ```
pub fn exportZero(
    comptime Program: type,
    comptime inst_name: []const u8,
) void {
    const InstructionType = @field(Program.instructions, inst_name);
    const Accounts = InstructionType.Accounts;
    const handler = @field(Program, inst_name);

    // Use ZeroCU's comptime offset calculation
    const data_lens = zero_cu.accountDataLengths(Accounts);
    const ix_data_offset = zero_cu.instructionDataOffset(data_lens);
    const disc: u64 = @bitCast(discriminator_mod.instructionDiscriminator(inst_name));

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            // Fast discriminator check
            const actual: *align(1) const u64 = @ptrCast(input + ix_data_offset);
            if (actual.* != disc) return 1;

            // Build ZeroCU context
            const zero_ctx = zero_cu.ZeroInstructionContext(Accounts).load(input);

            // Convert to Anchor Context
            const anchor_ctx = zeroToAnchorContext(Accounts, zero_ctx, &Program.id);

            // Call handler
            if (handler(anchor_ctx)) |_| return 0 else |_| return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Export zero-overhead multi-instruction entrypoint
///
/// Similar to `exportZero` but supports multiple instructions.
/// Adds ~2 CU overhead for discriminator dispatch.
///
/// ## Example
/// ```zig
/// comptime {
///     anchor.optimized.exportZeroMulti(Program, .{ "check", "verify" });
/// }
/// ```
pub fn exportZeroMulti(
    comptime Program: type,
    comptime inst_names: anytype,
) void {
    // All instructions must use the same account layout
    const FirstInst = @field(Program.instructions, inst_names[0]);
    const Accounts = FirstInst.Accounts;

    const data_lens = zero_cu.accountDataLengths(Accounts);
    const ix_data_offset = zero_cu.instructionDataOffset(data_lens);

    // Precompute all discriminators
    const Handler = struct {
        disc: u64,
        name: []const u8,
    };
    comptime var handlers: [inst_names.len]Handler = undefined;
    inline for (inst_names, 0..) |name, i| {
        handlers[i] = .{
            .disc = @bitCast(discriminator_mod.instructionDiscriminator(name)),
            .name = name,
        };
    }
    const handlers_final = handlers;

    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            const actual: *align(1) const u64 = @ptrCast(input + ix_data_offset);
            const zero_ctx = zero_cu.ZeroInstructionContext(Accounts).load(input);
            const anchor_ctx = zeroToAnchorContext(Accounts, zero_ctx, &Program.id);

            inline for (handlers_final) |h| {
                if (actual.* == h.disc) {
                    const handler = @field(Program, h.name);
                    if (handler(anchor_ctx)) |_| return 0 else |_| return 1;
                }
            }

            return 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Convert ZeroCU context to Anchor Context
fn zeroToAnchorContext(
    comptime Accounts: type,
    zero_ctx: zero_cu.ZeroInstructionContext(Accounts),
    program_id: *const PublicKey,
) context_mod.Context(Accounts) {
    // The zero_ctx.accounts already has the right structure
    // We just need to wrap it in Anchor's Context
    return context_mod.Context(Accounts){
        .accounts = convertZeroAccounts(Accounts, zero_ctx),
        .program_id = program_id,
        .remaining_accounts = &[_]AccountInfo{},
        .bumps = context_mod.Bumps{},
    };
}

/// Convert ZeroCU accounts to Anchor account types
fn convertZeroAccounts(
    comptime Accounts: type,
    zero_ctx: zero_cu.ZeroInstructionContext(Accounts),
) Accounts {
    const fields = std.meta.fields(Accounts);
    var result: Accounts = undefined;

    inline for (fields) |field| {
        const zero_acc = @field(zero_ctx.accounts, field.name);
        @field(result, field.name) = ZeroAccountWrapper(field.type, @TypeOf(zero_acc)){
            .zero = zero_acc,
        };
    }

    return result;
}

/// Wrapper to make ZeroCU account look like Anchor account
fn ZeroAccountWrapper(comptime _: type, comptime ZeroType: type) type {
    return struct {
        zero: ZeroType,

        const Self = @This();

        pub fn key(self: Self) *const PublicKey {
            return self.zero.id();
        }

        pub fn isSigner(self: Self) bool {
            return self.zero.isSigner();
        }

        pub fn isMut(self: Self) bool {
            return self.zero.isWritable();
        }

        // Forward other methods as needed
    };
}

// ============================================================================
// Standard Export (31+ CU)
// ============================================================================

/// Export an optimized entrypoint for a Program definition
///
/// This is the main integration point for standard Anchor API.
/// Uses SDK's Context.load() for full account parsing.
///
/// For lower CU, use `exportZero` or `exportZeroMulti`.
pub fn exportEntrypoint(comptime Program: type, comptime level: ValidationLevel) void {
    const S = struct {
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            @setRuntimeSafety(false);
            const result = processInput(Program, level, input);
            return if (result) |_| 0 else |_| 1;
        }
    };

    @export(&S.entrypoint, .{ .name = "entrypoint" });
}

/// Process raw SBF input and dispatch to handlers
fn processInput(
    comptime Program: type,
    comptime level: ValidationLevel,
    input: [*]u8,
) !void {
    // Parse accounts using SDK's Context (static [64]Account array)
    const ctx = sol.context.Context.load(input) catch {
        return error.AccountNotEnoughAccountKeys;
    };

    const data = ctx.data;

    if (data.len < 8) {
        return error.InstructionMissing;
    }

    const disc_u64: u64 = @bitCast(data[0..8].*);

    inline for (@typeInfo(Program.instructions).@"struct".decls) |decl| {
        const InstructionType = @field(Program.instructions, decl.name);
        if (@TypeOf(InstructionType) == type and @hasDecl(InstructionType, "Accounts")) {
            const expected_disc = comptime discriminator_mod.instructionDiscriminator(decl.name);
            const expected_u64: u64 = comptime @bitCast(expected_disc);

            if (disc_u64 == expected_u64) {
                const handler = @field(Program, decl.name);
                const Accounts = InstructionType.Accounts;
                const Args = if (@hasDecl(InstructionType, "Args")) InstructionType.Args else void;

                const anchor_ctx = try loadContextFromAccounts(Accounts, level, &Program.id, ctx.accounts[0..ctx.num_accounts]);

                if (Args == void) {
                    return handler(anchor_ctx);
                } else {
                    const args_data = data[8..];
                    const args = sol.borsh.deserializeExact(Args, args_data) catch {
                        return error.InstructionDidNotDeserialize;
                    };
                    return handler(anchor_ctx, args);
                }
            }
        }
    }

    return error.InstructionFallbackNotFound;
}

/// SDK Account type
const SdkAccount = sol.account.Account;

/// Load context from SDK Account array
fn loadContextFromAccounts(
    comptime Accounts: type,
    comptime level: ValidationLevel,
    program_id: *const PublicKey,
    sdk_accounts: []const SdkAccount,
) !context_mod.Context(Accounts) {
    const fields = @typeInfo(Accounts).@"struct".fields;

    if (sdk_accounts.len < fields.len) {
        return error.AccountNotEnoughAccountKeys;
    }

    var accounts: Accounts = undefined;

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = sdk_accounts[i].info();

        @field(accounts, field.name) = try loadAccountOptimized(FieldType, level, &info);
    }

    return context_mod.Context(Accounts).new(
        accounts,
        program_id,
        &[_]AccountInfo{},
        context_mod.Bumps{},
    );
}

/// Load a single account with optimized validation
fn loadAccountOptimized(
    comptime AccountType: type,
    comptime level: ValidationLevel,
    info: *const AccountInfo,
) !AccountType {
    if (@hasDecl(AccountType, "discriminator") and @hasDecl(AccountType, "DataType")) {
        return switch (level) {
            .full => AccountType.load(info),
            .minimal => loadAccountMinimal(AccountType, info),
            .unchecked => loadAccountUnchecked(AccountType, info),
        };
    }

    if (@hasDecl(AccountType, "load")) {
        return switch (level) {
            .full => AccountType.load(info),
            .minimal, .unchecked => loadSignerOptimized(AccountType, level, info),
        };
    }

    return info.*;
}

fn loadAccountMinimal(comptime AccountType: type, info: *const AccountInfo) !AccountType {
    if (info.data_len < AccountType.SPACE) {
        return error.AccountDiscriminatorNotFound;
    }

    if (!discriminator_mod.validateDiscriminatorFast(info.data, &AccountType.discriminator)) {
        return error.AccountDiscriminatorMismatch;
    }

    if (@hasDecl(AccountType, "HAS_SIGNER") and AccountType.HAS_SIGNER) {
        if (info.is_signer == 0) return error.ConstraintSigner;
    }

    if (@hasDecl(AccountType, "HAS_MUT") and AccountType.HAS_MUT) {
        if (info.is_writable == 0) return error.ConstraintMut;
    }

    const data_ptr: *AccountType.DataType = @ptrCast(@alignCast(
        info.data + discriminator_mod.DISCRIMINATOR_LENGTH,
    ));

    return AccountType{ .info = info, .data = data_ptr };
}

fn loadAccountUnchecked(comptime AccountType: type, info: *const AccountInfo) !AccountType {
    if (info.data_len < AccountType.SPACE) {
        return error.AccountDiscriminatorNotFound;
    }

    if (!discriminator_mod.validateDiscriminatorFast(info.data, &AccountType.discriminator)) {
        return error.AccountDiscriminatorMismatch;
    }

    const data_ptr: *AccountType.DataType = @ptrCast(@alignCast(
        info.data + discriminator_mod.DISCRIMINATOR_LENGTH,
    ));

    return AccountType{ .info = info, .data = data_ptr };
}

fn loadSignerOptimized(
    comptime SignerType: type,
    comptime level: ValidationLevel,
    info: *const AccountInfo,
) !SignerType {
    if (level == .minimal) {
        if (@hasDecl(SignerType, "HAS_SIGNER")) {
            if (SignerType.HAS_SIGNER and info.is_signer == 0) {
                return error.ConstraintSigner;
            }
        } else if (info.is_signer == 0) {
            return error.ConstraintSigner;
        }
    }

    return SignerType{ .info = info };
}

// ============================================================================
// Convenience re-exports
// ============================================================================

pub fn Instruction(comptime config: struct {
    Accounts: type,
    Args: type = void,
}) type {
    return struct {
        pub const Accounts = config.Accounts;
        pub const Args = config.Args;
    };
}
