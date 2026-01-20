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

/// Counter account data (8 bytes data, total 16 bytes with discriminator)
pub const CounterData = extern struct {
    /// Current count value
    count: u64,
};

// Total account size: 8 (discriminator) + 8 (count) = 16 bytes
const COUNTER_ACCOUNT_SIZE = 8 + @sizeOf(CounterData);

// ============================================================================
// Instruction Accounts (using size for offset calculation)
// ============================================================================

/// Accounts for initialize instruction
pub const InitializeAccounts = struct {
    /// Payer for account creation (must be signer, writable)
    payer: zero.Signer(0),
    /// Counter account to initialize (writable, 16 bytes total)
    counter: zero.Mut(COUNTER_ACCOUNT_SIZE),
    /// System program for account creation (renamed to avoid dynamic parsing)
    sys_account: zero.Readonly(0),
};

/// Accounts for increment instruction  
pub const IncrementAccounts = struct {
    /// Authority who can increment (must be signer)
    authority: zero.Signer(0),
    /// Counter account to modify (writable, 16 bytes total)
    counter: zero.Mut(COUNTER_ACCOUNT_SIZE),
};

/// Accounts for close instruction
pub const CloseAccounts = struct {
    /// Authority who can close (must be signer)
    authority: zero.Signer(0),
    /// Counter account to close (16 bytes total)
    counter: zero.Mut(COUNTER_ACCOUNT_SIZE),
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
    const accs = ctx.accounts();
    
    // Write discriminator (first 8 bytes)
    const disc = anchor.discriminator.accountDiscriminator("Counter");
    const data = accs.counter.data();
    @memcpy(data[0..8], &disc);
    
    // Write count (next 8 bytes, skip discriminator)
    const count_ptr: *align(1) u64 = @ptrCast(data[8..16]);
    count_ptr.* = args.initial;
}

/// Increment the counter
fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    const args = ctx.args(IncrementArgs);
    const accs = ctx.accounts();
    
    // Get counter data (skip 8-byte discriminator)
    const data = accs.counter.data();
    const count_ptr: *align(1) u64 = @ptrCast(data[8..16]);
    
    // Check for overflow
    const new_count = @addWithOverflow(count_ptr.*, args.amount);
    if (new_count[1] != 0) {
        return error.CounterOverflow;
    }

    count_ptr.* = new_count[0];
}

/// Close the counter account
fn close(ctx: zero.Ctx(CloseAccounts)) !void {
    const accs = ctx.accounts();
    
    // Transfer lamports to destination
    const counter_lamports = accs.counter.lamports();
    const dest_lamports = accs.destination.lamports();
    
    dest_lamports.* += counter_lamports.*;
    counter_lamports.* = 0;
    
    // Zero out counter data
    const data = accs.counter.data();
    @memset(data, 0);
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
