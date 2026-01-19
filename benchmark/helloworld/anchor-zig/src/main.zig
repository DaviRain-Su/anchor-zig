//! Anchor-Zig HelloWorld - Minimal implementation for CU benchmarking
//!
//! This is a minimal hello world program using the anchor-zig framework.
//! Used to measure the framework overhead compared to raw implementations.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;
const dsl = anchor.dsl;

// Define instruction using DSL
const Hello = dsl.Instr("hello", dsl.Accounts(.{}), void);

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("He11oWor1d1111111111111111111111111111111111");

    pub const instructions = struct {
        pub const hello = anchor.Instruction(.{
            .Accounts = Hello.Accs,
            .Args = Hello.Args,
        });
    };

    pub fn hello(ctx: Hello.Ctx) !void {
        _ = ctx;
        sol.log.log("Hello world!");
    }
};

fn processInstruction(
    program_id: *sol.PublicKey,
    accounts: []sol.Account,
    data: []const u8,
) sol.ProgramResult {
    const Entry = anchor.ProgramEntry(Program);
    var infos: [8]sol.account.Account.Info = undefined;
    const infos_slice = anchor.accountsToInfoSlice(accounts, infos[0..]);
    return Entry.processInstruction(program_id, infos_slice, data, .{});
}

comptime {
    sol.entrypoint(&processInstruction);
}
