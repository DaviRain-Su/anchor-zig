//! Counter Program using zero_cu API
//!
//! A simple counter program demonstrating:
//! - zero_cu account definitions with constraints
//! - Multi-instruction program with different account layouts
//! - IDL generation for TypeScript client
//!
//! ## Build
//! ```bash
//! cd counter
//! ../benchmark/solana-zig/zig build
//! ```
//!
//! ## Generate IDL
//! ```bash
//! cd counter
//! ./gen_idl.sh
//! # Output: idl/counter.json
//! ```

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const idl = anchor.idl_zero;
const sol = anchor.sdk;

// ============================================================================
// Program Configuration
// ============================================================================

pub const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("9YVfTx1E16vs7pzSSfC8wuqz19a4uGC1jtJP3tbKEHYC");

// ============================================================================
// Account Data Structures
// ============================================================================

/// Counter account data (8 bytes)
/// Used with discriminator: total account size = 8 (disc) + 8 (count) = 16 bytes
pub const CounterData = extern struct {
    /// Current count value
    count: u64,
};

// ============================================================================
// Instruction Accounts (using typed data access)
// ============================================================================

/// Accounts for initialize instruction
pub const InitializeAccounts = struct {
    /// Payer for account creation (must be signer, writable)
    payer: zero.Signer(0),
    /// Counter account to initialize (writable, typed as CounterData)
    counter: zero.Mut(CounterData),
    /// System program for account creation (renamed to avoid dynamic parsing)
    sys_account: zero.Readonly(0),
};

/// Accounts for increment instruction  
pub const IncrementAccounts = struct {
    /// Authority who can increment (must be signer)
    authority: zero.Signer(0),
    /// Counter account to modify (writable, typed as CounterData)
    counter: zero.Mut(CounterData),
};

/// Accounts for close instruction
pub const CloseAccounts = struct {
    /// Authority who can close (must be signer)
    authority: zero.Signer(0),
    /// Counter account to close (typed as CounterData)
    counter: zero.Mut(CounterData),
    /// Destination for remaining lamports
    destination: zero.Mut(0),
};

// ============================================================================
// Instruction Arguments
// ============================================================================

/// Arguments for initialize instruction
pub const InitializeArgs = extern struct {
    /// Initial count value
    initial: u64,
};

/// Arguments for increment instruction
pub const IncrementArgs = extern struct {
    /// Amount to increment by
    amount: u64,
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
        idl.InstructionWithDocs("initialize", InitializeAccounts, InitializeArgs, 
            "Initialize a new counter account with an initial value"),
        idl.InstructionWithDocs("increment", IncrementAccounts, IncrementArgs, 
            "Increment the counter by the specified amount"),
        idl.InstructionWithDocs("close", CloseAccounts, void, 
            "Close the counter account and return rent to destination"),
    };

    /// Account definitions for IDL
    pub const accounts = .{
        idl.AccountDefWithDocs("Counter", CounterData, 
            "Counter account that stores a count value"),
    };

    /// Custom errors
    pub const errors = enum(u32) {
        CounterOverflow = 6000,
        Unauthorized = 6001,
    };

    /// Events
    pub const events = .{
        idl.EventDef("CounterIncremented", struct {
            authority: sol.PublicKey,
            amount: u64,
            new_count: u64,
        }),
        idl.EventDef("CounterClosed", struct {
            authority: sol.PublicKey,
            final_count: u64,
        }),
    };
};

// ============================================================================
// Instruction Handlers (using zero.Ctx with typed data access)
// ============================================================================

/// Initialize a new counter account
fn initialize(ctx: zero.Ctx(InitializeAccounts)) !void {
    const args = ctx.args(InitializeArgs);
    
    // Write discriminator using helper function
    zero.writeDiscriminator(ctx.accounts.counter, "Counter");
    
    // Get typed mutable access to counter data (auto-skips discriminator)
    const counter = ctx.accounts.counter.getMut();
    counter.count = args.initial;
}

/// Increment the counter
fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    const args = ctx.args(IncrementArgs);
    
    // Get typed mutable access to counter data
    const counter = ctx.accounts.counter.getMut();
    
    // Check for overflow
    const new_count = @addWithOverflow(counter.count, args.amount);
    if (new_count[1] != 0) {
        return error.CounterOverflow;
    }

    counter.count = new_count[0];
}

/// Close the counter account
fn close(ctx: zero.Ctx(CloseAccounts)) !void {
    // Transfer lamports to destination
    const counter_lamports = ctx.accounts.counter.lamports();
    const dest_lamports = ctx.accounts.destination.lamports();
    
    dest_lamports.* += counter_lamports.*;
    counter_lamports.* = 0;
    
    // Zero out counter data
    const counter = ctx.accounts.counter.getMut();
    counter.count = 0;
}

// ============================================================================
// Program Entry Point
// ============================================================================

// Use zero.program() for multi-instruction programs with different account layouts
comptime {
    zero.program(.{
        zero.ix("initialize", InitializeAccounts, initialize),
        zero.ix("increment", IncrementAccounts, increment),
        zero.ix("close", CloseAccounts, close),
    });
}

// ============================================================================
// IDL Generation
// ============================================================================

/// Generate IDL JSON (called by gen_idl.zig)
pub fn generateIdl(allocator: std.mem.Allocator) ![]u8 {
    return idl.generateJson(allocator, Program);
}
