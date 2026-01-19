//! ZeroCU Program API with Constraint Validation
//!
//! Tests program() API with ixValidated() for automatic constraint validation.
//! Each instruction has different account layouts AND constraints.

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
        .owner = PROGRAM_ID, // Auto-validated
    }),
};

/// Accounts for verify instruction - with owner constraint
const VerifyAccounts = struct {
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID, // Auto-validated
    }),
};

/// Accounts for validate instruction - with signer + owner constraints
const ValidateAccounts = struct {
    authority: zero.Signer(0), // Must be signer
    target: zero.Account(struct { value: u8 }, .{
        .owner = PROGRAM_ID, // Auto-validated
    }),
};

// ============================================================================
// Handlers
// ============================================================================

/// Check with owner validation
pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
    // ctx.validate() already called by ixValidated
    // Just access the data
    _ = ctx.accounts.target.get().value;
}

/// Verify with owner validation
pub fn verify(ctx: zero.Ctx(VerifyAccounts)) !void {
    _ = ctx.accounts.target.get().value;
}

/// Validate with signer + owner validation
pub fn validate(ctx: zero.Ctx(ValidateAccounts)) !void {
    // Signer and owner are auto-validated
    _ = ctx.accounts.target.get().value;
}

// ============================================================================
// Program export using program() with ixValidated()
// ============================================================================

comptime {
    zero.program(.{
        zero.ixValidated("check", CheckAccounts, check),
        zero.ixValidated("verify", VerifyAccounts, verify),
        zero.ixValidated("validate", ValidateAccounts, validate),
    });
}
