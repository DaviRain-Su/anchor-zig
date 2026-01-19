//! Zero-CU Counter Program with IDL Generation
//!
//! A complete example showing:
//! - zero_cu account definitions with constraints
//! - Multi-instruction program
//! - IDL generation for TypeScript client
//!
//! ## Build & Deploy
//!
//! ```bash
//! cd examples/counter_zero_cu
//! ../../benchmark/solana-zig/zig build
//! solana program deploy zig-out/lib/counter_zero_cu.so
//! ```
//!
//! ## Generate IDL
//!
//! ```bash
//! ../../benchmark/solana-zig/zig build idl
//! # Output: target/idl/counter.json
//! ```

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const idl = anchor.idl_zero;
const sol = anchor.sdk;

// ============================================================================
// Program Configuration
// ============================================================================

pub const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("Counter111111111111111111111111111111111111");

// ============================================================================
// Account Data Structures
// ============================================================================

/// Counter account data
pub const CounterData = struct {
    /// Current count value
    count: u64,
    /// Authority who can modify the counter
    authority: sol.PublicKey,
    /// Bump seed for PDA derivation
    bump: u8,
};

/// Config account data
pub const ConfigData = struct {
    /// Maximum allowed count
    max_count: u64,
    /// Admin who can update config
    admin: sol.PublicKey,
};

// ============================================================================
// Instruction Accounts
// ============================================================================

/// Accounts for initialize instruction
pub const InitializeAccounts = struct {
    /// Payer for account creation
    payer: zero.Signer(0),
    /// Authority for the counter
    authority: zero.Signer(0),
    /// Counter account to initialize
    counter: zero.Mut(CounterData),
    /// System program for account creation
    system_program: zero.Readonly(0),
};

/// Accounts for increment instruction
pub const IncrementAccounts = struct {
    /// Authority who can increment
    authority: zero.Signer(0),
    /// Counter account to modify
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

/// Accounts for set_count instruction
pub const SetCountAccounts = struct {
    /// Authority who can set count
    authority: zero.Signer(0),
    /// Counter account to modify
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

/// Accounts for close instruction
pub const CloseAccounts = struct {
    /// Authority who can close
    authority: zero.Signer(0),
    /// Counter account to close
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
    /// Destination for remaining lamports
    destination: zero.Mut(0),
};

// ============================================================================
// Instruction Arguments
// ============================================================================

/// Arguments for set_count instruction
pub const SetCountArgs = struct {
    /// New count value
    value: u64,
};

// ============================================================================
// Program Definition (for IDL generation)
// ============================================================================

pub const Program = struct {
    pub const id = PROGRAM_ID;
    pub const name = "counter";
    pub const version = "0.1.0";
    pub const spec = "0.1.0";

    /// Instruction definitions for IDL
    pub const instructions = .{
        idl.Instruction("initialize", InitializeAccounts, void),
        idl.Instruction("increment", IncrementAccounts, void),
        idl.Instruction("set_count", SetCountAccounts, SetCountArgs),
        idl.Instruction("close", CloseAccounts, void),
    };

    /// Account definitions for IDL
    pub const accounts = .{
        idl.AccountDef("Counter", CounterData),
        idl.AccountDef("Config", ConfigData),
    };

    /// Custom errors
    pub const errors = enum(u32) {
        InvalidAuthority = 6000,
        CounterOverflow = 6001,
        CounterUnderflow = 6002,
        MaxCountExceeded = 6003,
    };
};

// ============================================================================
// Instruction Handlers
// ============================================================================

/// Initialize a new counter account
pub fn initialize(ctx: zero.Ctx(InitializeAccounts)) !void {
    // Write discriminator
    zero.writeDiscriminator(ctx.accounts.counter, "Counter");

    // Initialize data
    const data = ctx.accounts.counter.getMut();
    data.count = 0;
    data.authority = ctx.accounts.authority.id().*;
    data.bump = 0; // Would be set from PDA derivation
}

/// Increment the counter by 1
pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    const data = ctx.accounts.counter.getMut();

    // Check for overflow
    if (data.count == std.math.maxInt(u64)) {
        return error.CounterOverflow;
    }

    data.count += 1;
}

/// Set the counter to a specific value
pub fn set_count(ctx: zero.Ctx(SetCountAccounts)) !void {
    const args = ctx.args(SetCountArgs);
    ctx.accounts.counter.getMut().count = args.value;
}

/// Close the counter account
pub fn close(ctx: zero.Ctx(CloseAccounts)) !void {
    try zero.closeAccount(ctx.accounts.counter, ctx.accounts.destination);
}

// ============================================================================
// Program Entry Point
// ============================================================================

const std = @import("std");

comptime {
    // Multi-instruction export with different account layouts
    // Each instruction type needs its own entry for proper offset calculation

    // Note: In a real program, you'd use a unified accounts struct
    // or have separate entrypoints. This is a simplified example.

    zero.multi(IncrementAccounts, .{
        zero.inst("increment", increment),
    });
}

// ============================================================================
// IDL Generation Entry Point
// ============================================================================

/// Generate IDL JSON (called by build.zig idl step)
pub fn generateIdl(allocator: std.mem.Allocator) ![]u8 {
    return idl.generateJson(allocator, Program);
}
