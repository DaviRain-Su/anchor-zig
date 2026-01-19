//! Optimized Counter Example
//!
//! Demonstrates the optimized API that combines standard Anchor
//! abstractions with ZeroCU performance optimizations.
//!
//! Uses validation level: minimal (discriminator + signer checks)

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// ============================================================================
// Account Data Types
// ============================================================================

/// Counter account data
const CounterData = struct {
    count: u64,
    authority: sol.PublicKey,
    bump: u8,
};

// ============================================================================
// Account Wrappers (Standard Anchor API)
// ============================================================================

/// Counter account with discriminator and mut constraint
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .mut = true,
});

// ============================================================================
// Instruction Account Definitions
// ============================================================================

const InitializeAccounts = struct {
    authority: anchor.Signer,
    counter: Counter,
};

const IncrementAccounts = struct {
    authority: anchor.Signer,
    counter: Counter,
};

// ============================================================================
// Program Definition (Standard Anchor Style)
// ============================================================================

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58(
        "11111111111111111111111111111111"
    );

    /// Instruction definitions for IDL
    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
        });

        pub const increment = anchor.Instruction(.{
            .Accounts = IncrementAccounts,
        });
    };

    /// Initialize a new counter
    pub fn initialize(ctx: anchor.Context(InitializeAccounts)) !void {
        const counter = ctx.accounts.counter;
        counter.data.count = 0;
        counter.data.authority = ctx.accounts.authority.key().*;
    }

    /// Increment the counter
    pub fn increment(ctx: anchor.Context(IncrementAccounts)) !void {
        const counter = ctx.accounts.counter;

        // Verify authority (optional with minimal validation)
        if (!counter.data.authority.equals(ctx.accounts.authority.key().*)) {
            return error.Unauthorized;
        }

        counter.data.count += 1;
    }
};

// ============================================================================
// Optimized Entry Point
// ============================================================================

comptime {
    // Use minimal validation for better CU performance
    // Still checks discriminator and signer flags
    anchor.optimized.exportEntrypoint(Program, .minimal);
}
