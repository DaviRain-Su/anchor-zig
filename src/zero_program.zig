//! Zero-CU Program Framework
//!
//! Provides Anchor-style high-level API with zero runtime overhead.
//! All offsets and dispatch logic computed at comptime.
//!
//! Usage:
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//!
//! const TransferAccounts = struct {
//!     from: anchor.ZeroSigner(0),
//!     to: anchor.ZeroMut(0),
//! };
//!
//! pub const Program = anchor.ZeroProgram(.{
//!     .id = "MyProgram11111111111111111111111111111111",
//!     .instructions = .{
//!         .transfer = .{
//!             .Accounts = TransferAccounts,
//!             .handler = transfer,
//!         },
//!         .check = .{
//!             .Accounts = CheckAccounts,
//!             .handler = check,
//!         },
//!     },
//! });
//!
//! fn transfer(ctx: Program.Context(TransferAccounts)) !void {
//!     // Zero-overhead account access
//!     const from = ctx.accounts.from;
//!     const to = ctx.accounts.to;
//!     // ...
//! }
//!
//! comptime {
//!     Program.export();
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const discriminator_mod = @import("discriminator.zig");
const zero_cu = @import("zero_cu.zig");

/// Account type markers with data size
pub const ZeroSigner = zero_cu.ZeroSigner;
pub const ZeroMut = zero_cu.ZeroMut;
pub const ZeroReadonly = zero_cu.ZeroReadonly;

/// Instruction definition
pub fn InstructionDef(comptime Accounts: type, comptime Args: type) type {
    return struct {
        pub const AccountsType = Accounts;
        pub const ArgsType = Args;
    };
}

/// Re-export ZeroInstructionContext from zero_cu
pub const ZeroInstructionContext = zero_cu.ZeroInstructionContext;

/// Zero-overhead program definition
pub fn ZeroProgram(comptime config: anytype) type {
    return struct {
        pub const program_id = PublicKey.comptimeFromBase58(config.id);

        /// Get context type for an instruction's accounts
        pub fn Context(comptime Accounts: type) type {
            return ZeroInstructionContext(Accounts);
        }

        /// Export the entrypoint
        pub fn exportEntrypoint() void {
            @export(&entrypoint, .{ .name = "entrypoint" });
        }

        /// The actual entrypoint function
        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            return dispatch(input);
        }

        /// Dispatch to instruction handlers
        fn dispatch(input: [*]u8) u64 {
            const instructions = config.instructions;
            const inst_fields = std.meta.fields(@TypeOf(instructions));

            // Calculate ix_data_offset for first instruction to get discriminator
            // We need to check discriminator at a fixed location
            // For now, assume first instruction's account layout for disc offset
            // TODO: handle varying account layouts

            inline for (inst_fields) |field| {
                const inst = @field(instructions, field.name);
                const Accounts = inst.Accounts;
                const data_lens = zero_cu.accountDataLengths(Accounts);
                const ix_offset = zero_cu.instructionDataOffset(data_lens);

                const expected_disc = discriminator_mod.instructionDiscriminator(field.name);
                const expected_u64: u64 = @bitCast(expected_disc);

                const actual: *align(1) const u64 = @ptrCast(input + ix_offset);
                if (actual.* == expected_u64) {
                    const CtxType = ZeroInstructionContext(Accounts);
                    const ctx = CtxType.load(input);

                    const handler = inst.handler;
                    const result = handler(ctx);

                    if (result) |_| {
                        return 0;
                    } else |_| {
                        return 1;
                    }
                }
            }

            return 1; // Unknown instruction
        }
    };
}

/// Zero-CU Program wrapper
/// 
/// Generates entrypoint with zero-overhead dispatch.
/// All instruction matching and account access computed at comptime.
///
/// Usage:
/// ```zig
/// const anchor = @import("sol_anchor_zig");
/// const zero = anchor.zero_program;
///
/// const TransferAccounts = struct {
///     from: zero.ZeroSigner(0),
///     to: zero.ZeroMut(0),
/// };
///
/// pub const MyProgram = struct {
///     pub const id = anchor.sdk.PublicKey.comptimeFromBase58("...");
///
///     pub const instructions = struct {
///         pub const transfer = struct {
///             pub const Accounts = TransferAccounts;
///         };
///     };
///
///     pub fn transfer(ctx: zero.Context(TransferAccounts)) !void {
///         // Handler implementation
///     }
/// };
///
/// // Single line export!
/// comptime { zero.exportProgram(MyProgram); }
/// ```
pub fn Program(comptime ProgramDef: type) type {
    return struct {
        pub const id = ProgramDef.id;

        /// Context type for instruction handlers
        pub fn Context(comptime Accounts: type) type {
            return ZeroInstructionContext(Accounts);
        }

        /// Export the entrypoint (call from comptime block)
        pub fn exportEntrypoint() void {
            @export(&entrypoint, .{ .name = "entrypoint" });
        }

        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            return dispatch(input);
        }

        fn dispatch(input: [*]u8) u64 {
            const InstructionsType = ProgramDef.instructions;
            const decls = @typeInfo(InstructionsType).@"struct".decls;

            inline for (decls) |decl| {
                if (tryDispatch(decl.name, input)) |result| {
                    return result;
                }
            }

            return 1; // No matching instruction
        }

        fn tryDispatch(comptime name: []const u8, input: [*]u8) ?u64 {
            const InstructionsType = ProgramDef.instructions;
            const InstType = @field(InstructionsType, name);

            // Skip non-instruction decls
            if (!@hasDecl(InstType, "Accounts")) {
                return null;
            }

            const Accounts = InstType.Accounts;
            const CtxType = ZeroInstructionContext(Accounts);

            // Check discriminator at comptime-known offset
            const expected_disc = discriminator_mod.instructionDiscriminator(name);
            const expected_u64: u64 = @bitCast(expected_disc);
            const actual: *align(1) const u64 = @ptrCast(input + CtxType.ix_data_offset);

            if (actual.* != expected_u64) {
                return null;
            }

            // Load context and call handler
            const ctx = CtxType.load(input);
            const handler = @field(ProgramDef, name);

            if (handler(ctx)) |_| {
                return 0;
            } else |_| {
                return 1;
            }
        }
    };
}

/// Context type alias for cleaner handler signatures
pub fn Context(comptime Accounts: type) type {
    return ZeroInstructionContext(Accounts);
}

/// Generate entrypoint function for a single-instruction program
/// 
/// For programs with only one instruction, this generates the minimal
/// entrypoint code inline.
///
/// Usage:
/// ```zig
/// comptime {
///     @export(&zero.singleInstructionEntrypoint(
///         CheckAccounts,
///         "check", 
///         Program.check
///     ), .{ .name = "entrypoint" });
/// }
/// ```
pub fn singleInstructionEntrypoint(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) fn ([*]u8) callconv(.c) u64 {
    const Ctx = ZeroInstructionContext(Accounts);
    const disc: u64 = @bitCast(discriminator_mod.instructionDiscriminator(inst_name));

    return struct {
        fn entry(input: [*]u8) callconv(.c) u64 {
            const actual: *align(1) const u64 = @ptrCast(input + Ctx.ix_data_offset);
            if (actual.* != disc) return 1;

            const ctx = Ctx.load(input);
            if (handler(ctx)) |_| return 0 else |_| return 1;
        }
    }.entry;
}

/// Macro-like helper to generate and export entrypoint
/// 
/// Usage for single instruction:
/// ```zig
/// comptime {
///     zero.exportSingleInstruction(CheckAccounts, "check", Program.check);
/// }
/// ```
pub fn exportSingleInstruction(
    comptime Accounts: type,
    comptime inst_name: []const u8,
    comptime handler: anytype,
) void {
    const entry_fn = singleInstructionEntrypoint(Accounts, inst_name, handler);
    @export(&entry_fn, .{ .name = "entrypoint" });
}
