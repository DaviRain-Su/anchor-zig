//! Fast Anchor API
//!
//! Anchor-style abstractions with ZeroCU performance (5-7 CU).
//!
//! ## Features
//! - Familiar Anchor patterns (Signer, Account, Context)
//! - ZeroCU performance via comptime offset calculation
//! - Typed account data access
//!
//! ## Example
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const fast = anchor.fast;
//!
//! const CounterData = struct {
//!     count: u64,
//! };
//!
//! const IncrementAccounts = struct {
//!     authority: fast.Signer,
//!     counter: fast.Account(CounterData),
//! };
//!
//! pub const Program = struct {
//!     pub fn increment(ctx: fast.Context(IncrementAccounts)) !void {
//!         if (!ctx.accounts.authority.isSigner()) {
//!             return error.MissingSigner;
//!         }
//!         ctx.accounts.counter.data().count += 1;
//!     }
//! };
//!
//! comptime {
//!     fast.exportProgram(IncrementAccounts, .{
//!         fast.instruction("increment", Program.increment),
//!     });
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");
const zero_cu = @import("zero_cu.zig");

const PublicKey = sol.PublicKey;

// ============================================================================
// Account Type Markers
// ============================================================================

/// Signer account (must be transaction signer)
/// Data size: 0 bytes
pub const Signer = struct {
    pub const data_size: usize = 0;
    pub const is_signer = true;
    pub const is_writable = false;
    pub const has_typed_data = false;
};

/// Signer with mutable access
pub const SignerMut = struct {
    pub const data_size: usize = 0;
    pub const is_signer = true;
    pub const is_writable = true;
    pub const has_typed_data = false;
};

/// Typed account with data
pub fn Account(comptime T: type) type {
    return struct {
        pub const data_size = @sizeOf(T);
        pub const DataType = T;
        pub const is_signer = false;
        pub const is_writable = true;
        pub const has_typed_data = true;
    };
}

/// Readonly typed account
pub fn AccountReadonly(comptime T: type) type {
    return struct {
        pub const data_size = @sizeOf(T);
        pub const DataType = T;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = true;
    };
}

/// Raw account with specified size (no typed data)
pub fn RawAccount(comptime size: usize) type {
    return struct {
        pub const data_size = size;
        pub const is_signer = false;
        pub const is_writable = true;
        pub const has_typed_data = false;
    };
}

/// Readonly raw account
pub fn RawAccountReadonly(comptime size: usize) type {
    return struct {
        pub const data_size = size;
        pub const is_signer = false;
        pub const is_writable = false;
        pub const has_typed_data = false;
    };
}

// ============================================================================
// Context
// ============================================================================

/// Fast Context - Anchor-style with ZeroCU performance
pub fn Context(comptime Accounts: type) type {
    return zero_cu.ZeroInstructionContext(Accounts);
}

// ============================================================================
// Instruction Definition
// ============================================================================

/// Define an instruction with precomputed discriminator
pub fn instruction(comptime name: []const u8, comptime handler: anytype) struct { u64, @TypeOf(handler) } {
    return .{ @as(u64, @bitCast(discriminator_mod.instructionDiscriminator(name))), handler };
}

// ============================================================================
// Program Export
// ============================================================================

/// Export single-instruction program (5 CU)
///
/// Example:
/// ```zig
/// comptime {
///     fast.exportSingle(MyAccounts, "check", Program.check);
/// }
/// ```
pub fn exportSingle(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) void {
    zero_cu.entry(Accounts, inst_name, handler);
}

/// Export multi-instruction program (7 CU per instruction)
///
/// Example:
/// ```zig
/// comptime {
///     fast.exportProgram(MyAccounts, .{
///         fast.instruction("initialize", Program.initialize),
///         fast.instruction("increment", Program.increment),
///     });
/// }
/// ```
pub fn exportProgram(
    comptime Accounts: type,
    comptime handlers: anytype,
) void {
    zero_cu.multi(Accounts, handlers);
}

// ============================================================================
// Tests
// ============================================================================

test "Signer has zero data size" {
    try std.testing.expectEqual(@as(usize, 0), Signer.data_size);
}

test "Account has correct data size" {
    const TestData = struct { value: u64 };
    try std.testing.expectEqual(@as(usize, 8), Account(TestData).data_size);
}
