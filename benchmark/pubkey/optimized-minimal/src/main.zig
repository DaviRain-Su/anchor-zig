//! Optimized Entry Point - Minimal Validation
//!
//! Standard Anchor API with minimal validation level.
//! Result: ~31 CU

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// ============================================================================
// Instruction Accounts (Standard Anchor)
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

    pub const instructions = struct {
        pub const check = anchor.Instruction(.{
            .Accounts = CheckAccounts,
        });
    };

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
