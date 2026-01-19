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

/// Simpler API: Define program with struct-based instructions
pub fn Program(comptime ProgramDef: type) type {
    const program_id = ProgramDef.id;

    return struct {
        pub const id = program_id;

        pub fn Context(comptime Accounts: type) type {
            return ZeroInstructionContext(Accounts);
        }

        pub fn exportEntrypoint() void {
            @export(&entrypoint, .{ .name = "entrypoint" });
        }

        fn entrypoint(input: [*]u8) callconv(.c) u64 {
            return dispatch(input);
        }

        fn dispatch(input: [*]u8) u64 {
            return dispatchInner(input);
        }

        fn dispatchInner(input: [*]u8) u64 {
            const InstructionsType = ProgramDef.instructions;
            const decls = @typeInfo(InstructionsType).@"struct".decls;

            inline for (decls) |decl| {
                if (tryDispatch(decl.name, input)) |result| {
                    return result;
                }
            }

            return 1;
        }

        fn tryDispatch(comptime name: []const u8, input: [*]u8) ?u64 {
            const InstructionsType = ProgramDef.instructions;
            const InstType = @field(InstructionsType, name);

            if (!@hasDecl(InstType, "Accounts")) {
                return null;
            }

            const Accounts = InstType.Accounts;
            const CtxType = ZeroInstructionContext(Accounts);
            const ix_offset = CtxType.ix_data_offset;

            const expected_disc = discriminator_mod.instructionDiscriminator(name);
            const expected_u64: u64 = @bitCast(expected_disc);

            const actual: *align(1) const u64 = @ptrCast(input + ix_offset);
            if (actual.* != expected_u64) {
                return null;
            }

            const ctx = CtxType.load(input);
            const handler = @field(ProgramDef, name);
            const result = handler(ctx);

            if (result) |_| {
                return 0;
            } else |_| {
                return 1;
            }
        }
    };
}
