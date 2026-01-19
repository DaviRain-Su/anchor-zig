//! ZeroCU Single Instruction Example - Typed API
//!
//! Demonstrates zero_cu with typed account data.
//! Result: 5 CU (same as raw Zig)

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Data Type
// ============================================================================

/// Simple 1-byte marker data
const MarkerData = struct {
    value: u8,
};

// ============================================================================
// Account Definition - Typed!
// ============================================================================

const CheckAccounts = struct {
    target: zero.Readonly(MarkerData), // Typed as MarkerData
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "PubkeyComp111111111111111111111111111111111"
    );

    /// Check if account id equals owner id
    pub fn check(ctx: zero.Ctx(CheckAccounts)) !void {
        const target = ctx.accounts.target;

        // Can access typed data if needed
        _ = target.get().value;

        // Original comparison
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// ============================================================================
// Single-line entrypoint export (5 CU)
// ============================================================================

comptime {
    zero.entry(CheckAccounts, "check", Program.check);
}
