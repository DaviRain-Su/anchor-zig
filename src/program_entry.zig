//! Comptime program dispatch for Anchor-style instruction handling.
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/program.rs

const std = @import("std");
const sol = @import("solana_program_sdk");
const context_mod = @import("context.zig");
const discriminator_mod = @import("discriminator.zig");
const idl_mod = @import("idl.zig");
const anchor_error = @import("error.zig");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;
const ProgramError = sol.ProgramError;
const BorshError = sol.borsh.BorshError;

/// Instruction dispatch errors.
pub const DispatchError = error{
    InstructionMissing,
    InstructionFallbackNotFound,
    InstructionDidNotDeserialize,
};

/// Context passed to fallback handlers.
pub const FallbackContext = struct {
    program_id: *const PublicKey,
    accounts: []const AccountInfo,
    data: []const u8,
};

/// Dispatch configuration for program entry.
pub const DispatchConfig = struct {
    fallback: ?*const fn (ctx: FallbackContext) anyerror!void = null,
    error_mapper: ?*const fn (err: anyerror) ?ProgramError = null,
};

/// Generate a typed dispatcher for an Anchor-style Program definition.
pub fn ProgramEntry(comptime Program: type) type {
    comptime {
        if (!@hasDecl(Program, "id")) {
            @compileError("Program must define pub const id");
        }
        if (!@hasDecl(Program, "instructions")) {
            @compileError("Program must define pub const instructions");
        }
    }

    return struct {
        /// Dispatch instruction data to the matching handler.
        pub fn dispatch(
            program_id: *const PublicKey,
            accounts: []const AccountInfo,
            data: []const u8,
        ) !void {
            return dispatchWithConfig(program_id, accounts, data, .{});
        }

        /// Dispatch instruction data to the matching handler with custom config.
        pub fn dispatchWithConfig(
            program_id: *const PublicKey,
            accounts: []const AccountInfo,
            data: []const u8,
            config: DispatchConfig,
        ) !void {
            if (data.len < discriminator_mod.DISCRIMINATOR_LENGTH) {
                return DispatchError.InstructionMissing;
            }

            const disc = data[0..discriminator_mod.DISCRIMINATOR_LENGTH];

            inline for (@typeInfo(Program.instructions).@"struct".decls) |decl| {
                const InstructionType = @field(Program.instructions, decl.name);
                if (@TypeOf(InstructionType) == type) {
                    const expected = discriminator_mod.instructionDiscriminator(decl.name);
                    if (std.mem.eql(u8, disc, &expected)) {
                        if (!@hasDecl(Program, decl.name)) {
                            @compileError("Program is missing handler for instruction: " ++ decl.name);
                        }

                        const handler = @field(Program, decl.name);
                        const Accounts = InstructionType.Accounts;
                        const Args = InstructionType.Args;
                        const ctx = try context_mod.parseContext(Accounts, program_id, accounts);

                        if (Args == void) {
                            validateHandlerSignature(handler, decl.name, Accounts, void);
                            return handler(ctx);
                        }

                        const args_slice = data[discriminator_mod.DISCRIMINATOR_LENGTH..];
                        const args = sol.borsh.deserializeExact(Args, args_slice) catch {
                            return DispatchError.InstructionDidNotDeserialize;
                        };

                        validateHandlerSignature(handler, decl.name, Accounts, Args);
                        return handler(ctx, args);
                    }
                }
            }

            if (config.fallback) |fallback| {
                return fallback(.{
                    .program_id = program_id,
                    .accounts = accounts,
                    .data = data,
                });
            }

            if (@hasDecl(Program, "fallback")) {
                const fallback = @field(Program, "fallback");
                return fallback(.{
                    .program_id = program_id,
                    .accounts = accounts,
                    .data = data,
                });
            }

            return DispatchError.InstructionFallbackNotFound;
        }

        /// Dispatch instruction and map errors to ProgramError.
        pub fn processInstruction(
            program_id: *const PublicKey,
            accounts: []const AccountInfo,
            data: []const u8,
            config: DispatchConfig,
        ) sol.ProgramResult {
            dispatchWithConfig(program_id, accounts, data, config) catch |err| {
                if (config.error_mapper) |mapper| {
                    if (mapper(err)) |mapped| {
                        return .{ .err = mapped };
                    }
                }
                if (defaultMapError(err)) |mapped| {
                    return .{ .err = mapped };
                }
                return .{ .err = ProgramError.InvalidInstructionData };
            };
            return .{ .ok = {} };
        }
    };
}

fn validateHandlerSignature(
    comptime handler: anytype,
    comptime name: []const u8,
    comptime Accounts: type,
    comptime Args: type,
) void {
    const handler_type = @TypeOf(handler);
    if (@typeInfo(handler_type) != .@"fn") {
        @compileError("Handler " ++ name ++ " must be a function");
    }
    const fn_info = @typeInfo(handler_type).@"fn";
    const expected_params: usize = if (Args == void) 1 else 2;
    if (fn_info.params.len != expected_params) {
        @compileError("Handler " ++ name ++ " has wrong parameter count");
    }
    const ctx_type = context_mod.Context(Accounts);
    if (fn_info.params[0].type != ctx_type) {
        @compileError("Handler " ++ name ++ " first param must be Context(Accounts)");
    }
    if (Args != void and fn_info.params[1].type != Args) {
        @compileError("Handler " ++ name ++ " second param must match Args");
    }
}

fn defaultMapError(err: anyerror) ?ProgramError {
    const name = @errorName(err);
    if (std.meta.stringToEnum(anchor_error.AnchorError, name)) |anchor_err| {
        return ProgramError.custom(anchor_err.toU32());
    }
    if (err == DispatchError.InstructionMissing) {
        return ProgramError.custom(dispatchErrorToAnchor(DispatchError.InstructionMissing).toU32());
    }
    if (err == DispatchError.InstructionFallbackNotFound) {
        return ProgramError.custom(dispatchErrorToAnchor(DispatchError.InstructionFallbackNotFound).toU32());
    }
    if (err == DispatchError.InstructionDidNotDeserialize) {
        return ProgramError.custom(dispatchErrorToAnchor(DispatchError.InstructionDidNotDeserialize).toU32());
    }
    if (err == BorshError.UnexpectedEndOfInput or
        err == BorshError.ExtraDataAfterDeserialize or
        err == BorshError.InvalidBool or
        err == BorshError.InvalidOptionTag or
        err == BorshError.InvalidEnumTag or
        err == BorshError.InvalidUtf8 or
        err == BorshError.NanNotAllowed or
        err == BorshError.BufferTooSmall or
        err == BorshError.LengthOverflow)
    {
        return ProgramError.InvalidInstructionData;
    }
    return null;
}

fn dispatchErrorToAnchor(err: DispatchError) anchor_error.AnchorError {
    if (err == DispatchError.InstructionMissing) {
        return anchor_error.AnchorError.InstructionMissing;
    }
    if (err == DispatchError.InstructionFallbackNotFound) {
        return anchor_error.AnchorError.InstructionFallbackNotFound;
    }
    return anchor_error.AnchorError.InstructionDidNotDeserialize;
}

test "program entry dispatches by discriminator" {
    const Accounts = struct {};
    const Args = struct {
        value: u64,
    };

    const TestProgram = struct {
        pub const id = PublicKey.comptimeFromBase58("11111111111111111111111111111111");

        pub const instructions = struct {
            pub const initialize = idl_mod.Instruction(.{ .Accounts = Accounts, .Args = Args });
        };

        pub fn initialize(ctx: context_mod.Context(Accounts), args: Args) !void {
            _ = ctx;
            try std.testing.expectEqual(@as(u64, 7), args.value);
        }
    };

    var buffer: [discriminator_mod.DISCRIMINATOR_LENGTH + 8]u8 = undefined;
    const disc = discriminator_mod.instructionDiscriminator("initialize");
    @memcpy(buffer[0..discriminator_mod.DISCRIMINATOR_LENGTH], &disc);
    _ = try sol.borsh.serialize(Args, .{ .value = 7 }, buffer[discriminator_mod.DISCRIMINATOR_LENGTH..]);

    const entry = ProgramEntry(TestProgram);
    try entry.dispatch(&TestProgram.id, &[_]AccountInfo{}, buffer[0..]);
}

test "program entry fallback is invoked" {
    const TestProgram = struct {
        pub const id = PublicKey.comptimeFromBase58("11111111111111111111111111111111");
        pub const instructions = struct {};
    };

    const FallbackState = struct {
        var hit: bool = false;

        fn handle(ctx: FallbackContext) !void {
            _ = ctx;
            hit = true;
        }
    };

    const entry = ProgramEntry(TestProgram);
    const data = [_]u8{0} ** 8;
    try entry.dispatchWithConfig(&TestProgram.id, &[_]AccountInfo{}, &data, .{
        .fallback = FallbackState.handle,
    });
    try std.testing.expect(FallbackState.hit);
}
