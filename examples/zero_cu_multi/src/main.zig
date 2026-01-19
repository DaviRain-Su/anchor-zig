//! ZeroCU Multi-Instruction Example with Typed Data
//!
//! Demonstrates the zero_cu API with typed account data.
//! No more manual pointer casts!

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// ============================================================================
// Account Data Types
// ============================================================================

/// Counter data stored in account
const CounterData = struct {
    count: u64,
};

// ============================================================================
// Account Layout - Now with typed data!
// ============================================================================

const ProgramAccounts = struct {
    authority: zero.Signer(0),           // Signer, no data
    counter: zero.Mut(CounterData),      // Writable, typed as CounterData
};

// ============================================================================
// Program
// ============================================================================

pub const Program = struct {
    pub const id = anchor.sdk.PublicKey.comptimeFromBase58(
        "ZeroCU11111111111111111111111111111111111111"
    );

    /// Initialize counter to 0
    pub fn initialize(ctx: zero.Ctx(ProgramAccounts)) !void {
        // Automatic signer check via type
        if (!ctx.accounts.authority.isSigner()) {
            return error.MissingSigner;
        }

        // Typed access - no pointer casts!
        ctx.accounts.counter.getMut().count = 0;
    }

    /// Increment counter
    pub fn increment(ctx: zero.Ctx(ProgramAccounts)) !void {
        if (!ctx.accounts.authority.isSigner()) {
            return error.MissingSigner;
        }

        // Direct field access
        ctx.accounts.counter.getMut().count += 1;
    }

    /// Get counter value
    pub fn get(ctx: zero.Ctx(ProgramAccounts)) !void {
        // Readonly typed access
        const count = ctx.accounts.counter.get().count;
        _ = count;
    }
};

// ============================================================================
// Multi-instruction export (7 CU each)
// ============================================================================

comptime {
    zero.multi(ProgramAccounts, .{
        zero.inst("initialize", Program.initialize),
        zero.inst("increment", Program.increment),
        zero.inst("get", Program.get),
    });
}
