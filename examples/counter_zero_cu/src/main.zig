//! Zero-CU Counter Program with IDL Generation
//!
//! A complete example showing:
//! - zero_cu account definitions with constraints
//! - Multi-instruction program
//! - IDL generation for TypeScript client
//! - Optional accounts
//! - Union types (Rust enums with data)

const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const idl = anchor.idl_zero;
const sol = anchor.sdk;
const std = @import("std");

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
    /// Optional label
    label: ?[32]u8,
};

/// Config account data
pub const ConfigData = struct {
    /// Maximum allowed count
    max_count: u64,
    /// Admin who can update config
    admin: sol.PublicKey,
    /// Fee in lamports
    fee: u64,
};

/// Counter action type (demonstrates union/enum with data)
pub const CounterAction = union(enum) {
    /// Increment by 1
    increment: void,
    /// Decrement by 1
    decrement: void,
    /// Set to specific value
    set: u64,
    /// Reset to zero
    reset: void,
};

/// Counter status enum
pub const CounterStatus = enum(u8) {
    active,
    paused,
    closed,
};

// ============================================================================
// Instruction Accounts
// ============================================================================

/// Accounts for initialize instruction
pub const InitializeAccounts = struct {
    /// Payer for account creation (must be signer, writable)
    payer: zero.Signer(0),
    /// Authority for the counter
    authority: zero.Signer(0),
    /// Counter account to initialize
    counter: zero.Mut(CounterData),
    /// System program for account creation
    system_program: zero.Program(sol.system_program.ID),
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
    /// Optional config for fee collection
    config: zero.Optional(zero.Readonly(ConfigData)),
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

/// Accounts for action instruction (demonstrates union args)
pub const ActionAccounts = struct {
    authority: zero.Signer(0),
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

// ============================================================================
// Instruction Arguments
// ============================================================================

/// Arguments for set_count instruction
pub const SetCountArgs = struct {
    /// New count value
    value: u64,
};

/// Arguments for action instruction
pub const ActionArgs = struct {
    /// Action to perform
    action: CounterAction,
};

/// Arguments for initialize with optional label
pub const InitializeArgs = struct {
    /// Optional label for the counter
    label: ?[32]u8,
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
        idl.InstructionWithDocs("initialize", InitializeAccounts, InitializeArgs, "Initialize a new counter account"),
        idl.InstructionWithDocs("increment", IncrementAccounts, void, "Increment the counter by 1"),
        idl.InstructionWithDocs("set_count", SetCountAccounts, SetCountArgs, "Set the counter to a specific value"),
        idl.InstructionWithDocs("close", CloseAccounts, void, "Close the counter account and reclaim rent"),
        idl.Instruction("action", ActionAccounts, ActionArgs),
    };

    /// Account definitions for IDL
    pub const accounts = .{
        idl.AccountDefWithDocs("Counter", CounterData, "Counter account that stores a count value"),
        idl.AccountDef("Config", ConfigData),
    };

    /// Custom errors
    pub const errors = enum(u32) {
        InvalidAuthority = 6000,
        CounterOverflow = 6001,
        CounterUnderflow = 6002,
        MaxCountExceeded = 6003,
        CounterPaused = 6004,
    };

    /// Events
    pub const events = .{
        idl.EventDef("CounterUpdated", struct {
            previous: u64,
            current: u64,
            authority: sol.PublicKey,
        }),
        idl.EventDef("CounterClosed", struct {
            final_count: u64,
            authority: sol.PublicKey,
        }),
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
    const args = ctx.args(InitializeArgs);

    data.count = 0;
    data.authority = ctx.accounts.authority.id().*;
    data.bump = 0;
    data.label = args.label;
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

/// Perform an action on the counter
pub fn action(ctx: zero.Ctx(ActionAccounts)) !void {
    const args = ctx.args(ActionArgs);
    const data = ctx.accounts.counter.getMut();

    switch (args.action) {
        .increment => {
            if (data.count == std.math.maxInt(u64)) return error.CounterOverflow;
            data.count += 1;
        },
        .decrement => {
            if (data.count == 0) return error.CounterUnderflow;
            data.count -= 1;
        },
        .set => |value| {
            data.count = value;
        },
        .reset => {
            data.count = 0;
        },
    }
}

// ============================================================================
// Program Entry Point
// ============================================================================

comptime {
    zero.multi(IncrementAccounts, .{
        zero.inst("increment", increment),
    });
}

// ============================================================================
// IDL Generation Helper
// ============================================================================

/// Generate IDL JSON (for build.zig idl step)
pub fn generateIdl(allocator: std.mem.Allocator) ![]u8 {
    return idl.generateJson(allocator, Program);
}
