//! Optimized Simple Example
//!
//! A minimal program to test the optimized entry point.
//! Uses Signer only (no account data discriminator checks).

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// ============================================================================
// Instruction Account Definitions
// ============================================================================

const CheckAccounts = struct {
    authority: anchor.Signer,
};

// ============================================================================
// Program Definition
// ============================================================================

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58(
        "11111111111111111111111111111111"
    );

    /// Instruction definitions
    pub const instructions = struct {
        pub const check = anchor.Instruction(.{
            .Accounts = CheckAccounts,
        });
    };

    /// Just verify we can access the signer
    pub fn check(ctx: anchor.Context(CheckAccounts)) !void {
        _ = ctx.accounts.authority.key();
    }
};

// ============================================================================
// Optimized Entry Point (minimal validation)
// ============================================================================

comptime {
    anchor.optimized.exportEntrypoint(Program, .minimal);
}
