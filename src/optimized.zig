//! Optimized Anchor Entry Point
//!
//! This module provides an optimized entry point generator that combines
//! Anchor's high-level API with ZeroCU's performance optimizations.
//!
//! ## Features
//!
//! - Standard Anchor API (Account, Signer, Context)
//! - Zero-overhead discriminator matching (u64 comparison)
//! - Optional validation tiers (full, minimal, none)
//! - Comptime-optimized dispatch
//!
//! ## Example
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//!
//! // Standard Anchor definitions
//! const CounterData = struct {
//!     count: u64,
//!     authority: anchor.sdk.PublicKey,
//! };
//!
//! const Counter = anchor.Account(CounterData, .{
//!     .discriminator = anchor.accountDiscriminator("Counter"),
//!     .mut = true,
//! });
//!
//! const IncrementAccounts = struct {
//!     authority: anchor.Signer,
//!     counter: Counter,
//! };
//!
//! pub const Program = struct {
//!     pub const id = anchor.sdk.PublicKey.comptimeFromBase58("...");
//!
//!     pub const instructions = struct {
//!         pub const increment = anchor.Instruction(.{
//!             .Accounts = IncrementAccounts,
//!         });
//!     };
//!
//!     pub fn increment(ctx: anchor.Context(IncrementAccounts)) !void {
//!         ctx.accounts.counter.data.count += 1;
//!     }
//! };
//!
//! // Optimized entry point (choose validation level)
//! comptime {
//!     anchor.optimized.exportEntrypoint(Program, .minimal);
//! }
//! ```
//!
//! ## Validation Levels
//!
//! | Level    | Discriminator | Owner | Signer | Address | CU Overhead |
//! |----------|---------------|-------|--------|---------|-------------|
//! | full     | ✓             | ✓     | ✓      | ✓       | ~150 CU     |
//! | minimal  | ✓             | ✗     | ✓      | ✗       | ~50 CU      |
//! | unchecked| ✓             | ✗     | ✗      | ✗       | ~10 CU      |

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");
const context_mod = @import("context.zig");

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

/// Export an optimized entrypoint for a Program definition
///
/// This is the main integration point. It generates an entrypoint that:
/// 1. Uses fast u64 discriminator comparison
/// 2. Applies the specified validation level
/// 3. Dispatches to the correct handler
///
/// Example:
/// ```zig
/// comptime {
///     anchor.optimized.exportEntrypoint(Program, .minimal);
/// }
/// ```
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
    // Parse accounts using SDK's Context (static [64]Account array, ~37 CU)
    const ctx = sol.context.Context.load(input) catch {
        return error.AccountNotEnoughAccountKeys;
    };

    // Get instruction data
    const data = ctx.data;

    // Fast discriminator check
    if (data.len < 8) {
        return error.InstructionMissing;
    }

    const disc_u64: u64 = @bitCast(data[0..8].*);

    // Dispatch based on discriminator
    inline for (@typeInfo(Program.instructions).@"struct".decls) |decl| {
        const InstructionType = @field(Program.instructions, decl.name);
        if (@TypeOf(InstructionType) == type and @hasDecl(InstructionType, "Accounts")) {
            const expected_disc = comptime discriminator_mod.instructionDiscriminator(decl.name);
            const expected_u64: u64 = comptime @bitCast(expected_disc);

            if (disc_u64 == expected_u64) {
                const handler = @field(Program, decl.name);
                const Accounts = InstructionType.Accounts;
                const Args = if (@hasDecl(InstructionType, "Args")) InstructionType.Args else void;

                // Load accounts with specified validation level (use Account directly)
                const anchor_ctx = try loadContextFromAccounts(Accounts, level, &Program.id, ctx.accounts[0..ctx.num_accounts]);

                // Call handler
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

/// Load context from SDK Account array (avoids AccountInfo conversion)
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

    // For remaining accounts, we need to create AccountInfo slice
    // For now, just pass empty slice (most programs don't use remaining accounts)
    return context_mod.Context(Accounts).new(
        accounts,
        program_id,
        &[_]AccountInfo{},
        context_mod.Bumps{},
    );
}

/// Load context with optimized validation (from AccountInfo array)
fn loadContextOptimized(
    comptime Accounts: type,
    comptime level: ValidationLevel,
    program_id: *const PublicKey,
    infos: []const AccountInfo,
) !context_mod.Context(Accounts) {
    const fields = @typeInfo(Accounts).@"struct".fields;

    if (infos.len < fields.len) {
        return error.AccountNotEnoughAccountKeys;
    }

    var accounts: Accounts = undefined;

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        @field(accounts, field.name) = try loadAccountOptimized(FieldType, level, info);
    }

    return context_mod.Context(Accounts).new(
        accounts,
        program_id,
        if (infos.len > fields.len) infos[fields.len..] else &[_]AccountInfo{},
        context_mod.Bumps{},
    );
}

/// Load a single account with optimized validation
fn loadAccountOptimized(
    comptime AccountType: type,
    comptime level: ValidationLevel,
    info: *const AccountInfo,
) !AccountType {
    // Check if it's an Account wrapper with discriminator
    if (@hasDecl(AccountType, "discriminator") and @hasDecl(AccountType, "DataType")) {
        return switch (level) {
            .full => AccountType.load(info),
            .minimal => loadAccountMinimal(AccountType, info),
            .unchecked => loadAccountUnchecked(AccountType, info),
        };
    }

    // For Signer and other simple types
    if (@hasDecl(AccountType, "load")) {
        return switch (level) {
            .full => AccountType.load(info),
            .minimal, .unchecked => loadSignerOptimized(AccountType, level, info),
        };
    }

    // Raw AccountInfo
    return info.*;
}

/// Load Account with minimal validation (discriminator + mut/signer flags only)
fn loadAccountMinimal(
    comptime AccountType: type,
    info: *const AccountInfo,
) !AccountType {
    // Fast discriminator check
    if (info.data_len < AccountType.SPACE) {
        return error.AccountDiscriminatorNotFound;
    }

    if (!discriminator_mod.validateDiscriminatorFast(info.data, &AccountType.discriminator)) {
        return error.AccountDiscriminatorMismatch;
    }

    // Signer check (if required)
    if (@hasDecl(AccountType, "HAS_SIGNER") and AccountType.HAS_SIGNER) {
        if (info.is_signer == 0) {
            return error.ConstraintSigner;
        }
    }

    // Mut check (if required)
    if (@hasDecl(AccountType, "HAS_MUT") and AccountType.HAS_MUT) {
        if (info.is_writable == 0) {
            return error.ConstraintMut;
        }
    }

    const data_ptr: *AccountType.DataType = @ptrCast(@alignCast(
        info.data + discriminator_mod.DISCRIMINATOR_LENGTH,
    ));

    return AccountType{
        .info = info,
        .data = data_ptr,
    };
}

/// Load Account with only discriminator check
fn loadAccountUnchecked(
    comptime AccountType: type,
    info: *const AccountInfo,
) !AccountType {
    if (info.data_len < AccountType.SPACE) {
        return error.AccountDiscriminatorNotFound;
    }

    // Still check discriminator (critical for security)
    if (!discriminator_mod.validateDiscriminatorFast(info.data, &AccountType.discriminator)) {
        return error.AccountDiscriminatorMismatch;
    }

    const data_ptr: *AccountType.DataType = @ptrCast(@alignCast(
        info.data + discriminator_mod.DISCRIMINATOR_LENGTH,
    ));

    return AccountType{
        .info = info,
        .data = data_ptr,
    };
}

/// Load Signer with optimized validation
fn loadSignerOptimized(
    comptime SignerType: type,
    comptime level: ValidationLevel,
    info: *const AccountInfo,
) !SignerType {
    // For minimal level, still check signer flag
    if (level == .minimal) {
        if (@hasDecl(SignerType, "HAS_SIGNER")) {
            if (SignerType.HAS_SIGNER and info.is_signer == 0) {
                return error.ConstraintSigner;
            }
        } else if (info.is_signer == 0) {
            return error.ConstraintSigner;
        }
    }

    // For unchecked, skip all validation
    return SignerType{ .info = info };
}

// ============================================================================
// Convenience re-exports
// ============================================================================

/// Instruction definition helper (same as idl.Instruction)
pub fn Instruction(comptime config: struct {
    Accounts: type,
    Args: type = void,
}) type {
    return struct {
        pub const Accounts = config.Accounts;
        pub const Args = config.Args;
    };
}

// ============================================================================
// Tests
// ============================================================================

test "ValidationLevel enum" {
    try std.testing.expect(@intFromEnum(ValidationLevel.full) == 0);
    try std.testing.expect(@intFromEnum(ValidationLevel.minimal) == 1);
    try std.testing.expect(@intFromEnum(ValidationLevel.unchecked) == 2);
}
