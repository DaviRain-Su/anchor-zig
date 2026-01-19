//! Solana Program Template using zero_cu
//!
//! This is the recommended template for all Solana programs using anchor-zig.
//! It uses program() + ixValidated() for maximum flexibility and safety.
//!
//! Features:
//! - Different account layouts per instruction ✅
//! - Automatic constraint validation ✅
//! - IDL generation support ✅
//! - ~18 CU overhead per instruction ✅

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const idl = anchor.idl_zero;
const sol = anchor.sdk;

// ============================================================================
// Program Configuration
// ============================================================================

/// Program ID - replace with your deployed program address
pub const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("YourProgram11111111111111111111111111111111");

// ============================================================================
// Account Data Structures
// ============================================================================

/// Example: Counter account data
pub const CounterData = struct {
    /// Current count value
    count: u64,
    /// Authority who can modify this counter
    authority: sol.PublicKey,
    /// Bump seed for PDA (if applicable)
    bump: u8,
};

// ============================================================================
// Instruction Accounts
// ============================================================================

/// Initialize - create new counter
pub const InitializeAccounts = struct {
    /// Payer for rent
    payer: zero.Signer(0),
    /// New counter account
    counter: zero.Mut(CounterData),
    /// System program
    system_program: zero.Readonly(0),
};

/// Increment - increase counter value
pub const IncrementAccounts = struct {
    /// Must be the counter's authority
    authority: zero.Signer(0),
    /// Counter to modify
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

/// Close - close counter and reclaim rent
pub const CloseAccounts = struct {
    /// Must be the counter's authority
    authority: zero.Signer(0),
    /// Counter to close
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

pub const InitializeArgs = struct {
    /// Initial count value
    initial_count: u64,
};

pub const IncrementArgs = struct {
    /// Amount to add
    amount: u64,
};

// ============================================================================
// Program Definition (for IDL generation)
// ============================================================================

pub const Program = struct {
    pub const id = PROGRAM_ID;
    pub const name = "my_program";
    pub const version = "0.1.0";
    pub const spec = "0.1.0";

    pub const instructions = .{
        idl.InstructionWithDocs("initialize", InitializeAccounts, InitializeArgs,
            "Initialize a new counter account"),
        idl.InstructionWithDocs("increment", IncrementAccounts, IncrementArgs,
            "Increment the counter by the specified amount"),
        idl.InstructionWithDocs("close", CloseAccounts, void,
            "Close the counter and return rent to destination"),
    };

    pub const accounts = .{
        idl.AccountDefWithDocs("Counter", CounterData,
            "Counter account that stores a count value and authority"),
    };

    pub const errors = enum(u32) {
        /// Counter value would overflow
        CounterOverflow = 6000,
        /// Caller is not the authority
        Unauthorized = 6001,
    };
};

// ============================================================================
// Instruction Handlers
// ============================================================================

/// Initialize a new counter
pub fn initialize(ctx: zero.Ctx(InitializeAccounts)) !void {
    const args = ctx.args(InitializeArgs);

    // Write discriminator
    zero.writeDiscriminator(ctx.accounts.counter, "Counter");

    // Initialize data
    const data = ctx.accounts.counter.getMut();
    data.count = args.initial_count;
    data.authority = ctx.accounts.payer.id().*;
    data.bump = 0;
}

/// Increment the counter
pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    const args = ctx.args(IncrementArgs);
    const data = ctx.accounts.counter.getMut();

    // Safe addition with overflow check
    const result = @addWithOverflow(data.count, args.amount);
    if (result[1] != 0) {
        return error.CounterOverflow;
    }
    data.count = result[0];
}

/// Close the counter
pub fn close(ctx: zero.Ctx(CloseAccounts)) !void {
    try zero.closeAccount(ctx.accounts.counter, ctx.accounts.destination);
}

// ============================================================================
// Program Entry Point (RECOMMENDED PATTERN)
// ============================================================================

comptime {
    zero.program(.{
        zero.ixValidated("initialize", InitializeAccounts, initialize),
        zero.ixValidated("increment", IncrementAccounts, increment),
        zero.ixValidated("close", CloseAccounts, close),
    });
}

// ============================================================================
// IDL Generation
// ============================================================================

pub fn generateIdl(allocator: std.mem.Allocator) ![]u8 {
    return idl.generateJson(allocator, Program);
}
