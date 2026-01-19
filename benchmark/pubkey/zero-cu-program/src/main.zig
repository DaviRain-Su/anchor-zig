//! ZeroCU Program API Test
//!
//! Same logic as solana-program-rosetta/pubkey but using zero.program() API.
//! Tests CU cost when using different account layouts per instruction.
//!
//! Compare with:
//! - zig-raw: 5 CU (baseline)
//! - zero-cu-single: 5 CU (entry API)
//! - zero-cu-multi: 7 CU (multi API, same layout)
//! - zero-cu-program: ? CU (program API, different layouts)

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Definitions (simulating different layouts)
// ============================================================================

/// Accounts for check instruction
const CheckAccounts = struct {
    target: zero.Readonly(1),
};

/// Accounts for verify instruction (same as check but different struct)
const VerifyAccounts = struct {
    target: zero.Readonly(1),
};

/// Accounts for validate instruction (slightly different - adds signer requirement)
const ValidateAccounts = struct {
    authority: zero.Signer(0),
    target: zero.Readonly(1),
};

// ============================================================================
// Handlers
// ============================================================================

/// Check if account id equals owner id
pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
    const target = ctx.accounts.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

/// Same as check but with different account type
pub fn verify(ctx: zero.Ctx(VerifyAccounts)) !void {
    const target = ctx.accounts.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

/// Validate with authority check
pub fn validate(ctx: zero.Ctx(ValidateAccounts)) !void {
    if (!ctx.accounts.authority.isSigner()) {
        return error.MissingSigner;
    }
    const target = ctx.accounts.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

// ============================================================================
// Program export using program() API
// ============================================================================

comptime {
    zero.program(.{
        zero.ix("check", CheckAccounts, check),
        zero.ix("verify", VerifyAccounts, verify),
        zero.ix("validate", ValidateAccounts, validate),
    });
}
