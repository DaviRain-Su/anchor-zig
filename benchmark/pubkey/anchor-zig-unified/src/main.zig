//! Anchor-Zig Pubkey Comparison - Unified Zero-CU API
//!
//! Anchor-style API with zero runtime overhead.
//! Clean, readable code that compiles to raw performance.

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_program;

// ============================================================================
// Account Definitions
// ============================================================================

const CheckAccounts = struct {
    target: zero.ZeroReadonly(1), // Account with 1 byte data
};

// ============================================================================
// Program Definition - Anchor compatible structure
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "PubkeyComp111111111111111111111111111111111"
    );

    pub const instructions = struct {
        pub const check = struct {
            pub const Accounts = CheckAccounts;
        };
    };

    /// Instruction handler with named account access
    pub fn check(ctx: zero.Context(CheckAccounts)) !void {
        const target = ctx.accounts.target;

        // High-level API - compiles to zero overhead
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Single-line entrypoint export!
// ============================================================================

comptime {
    zero.exportSingleInstruction(CheckAccounts, "check", Program.check);
}
