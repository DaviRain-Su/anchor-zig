//! ZeroCU Program API Test
//!
//! Same logic as solana-program-rosetta/pubkey but using zero.program() API.
//! Tests CU cost with account constraints but using ix() (not ixValidated).

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// Program ID for owner constraint
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

// ============================================================================
// Account Definitions with Constraints
// ============================================================================

/// Accounts for check instruction - with owner constraint
const CheckAccounts = struct {
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID,
    }),
};

/// Accounts for verify instruction - with owner constraint
const VerifyAccounts = struct {
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID,
    }),
};

/// Accounts for validate instruction - with signer + owner constraints
const ValidateAccounts = struct {
    authority: zero.Signer(0),
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID,
    }),
};

// ============================================================================
// Handlers - same logic as rosetta pubkey
// ============================================================================

/// Check if account id equals owner id
pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
    const accs = ctx.accounts();
    const target = accs.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

/// Same as check but with different account type
pub fn verify(ctx: zero.Ctx(VerifyAccounts)) !void {
    const accs = ctx.accounts();
    const target = accs.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

/// Validate with authority check
pub fn validate(ctx: zero.Ctx(ValidateAccounts)) !void {
    const accs = ctx.accounts();
    if (!accs.authority.isSigner()) {
        return error.MissingSigner;
    }
    const target = accs.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

// ============================================================================
// Program export using ixValidated() - WITH auto validation
// ============================================================================

comptime {
    zero.program(.{
        zero.ixValidated("check", CheckAccounts, check),
        zero.ixValidated("verify", VerifyAccounts, verify),
        zero.ixValidated("validate", ValidateAccounts, validate),
    });
}
