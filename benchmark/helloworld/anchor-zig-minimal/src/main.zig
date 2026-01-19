//! Anchor-Zig HelloWorld - Minimal entry point (no accountsToInfoSlice)
//!
//! Uses direct dispatch to minimize overhead.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const EmptyAccounts = struct {};

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("He11oWor1d1111111111111111111111111111111111");

    pub const instructions = struct {
        pub const hello = anchor.Instruction(.{
            .Accounts = EmptyAccounts,
            .Args = void,
        });
    };

    pub fn hello(ctx: anchor.Context(EmptyAccounts)) !void {
        _ = ctx;
        sol.log.log("Hello world!");
    }
};

fn processInstruction(
    program_id: *sol.PublicKey,
    accounts: []sol.Account,
    data: []const u8,
) sol.ProgramResult {
    _ = accounts;
    
    // Direct dispatch without accountsToInfoSlice
    const Entry = anchor.ProgramEntry(Program);
    return Entry.processInstruction(program_id, &[_]sol.account.Account.Info{}, data, .{});
}

comptime {
    sol.entrypoint(&processInstruction);
}
