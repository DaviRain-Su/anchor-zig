//! Anchor-Zig Pubkey Comparison
//!
//! Compares account id with owner id using anchor-zig framework.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const CheckAccounts = struct {
    target: anchor.InterfaceAccountInfo(.{}),
};

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("PubkeyComp111111111111111111111111111111111");

    pub const instructions = struct {
        pub const check = anchor.Instruction(.{
            .Accounts = CheckAccounts,
            .Args = void,
        });
    };

    pub fn check(ctx: anchor.Context(CheckAccounts)) !void {
        const target_info = ctx.accounts.target.toAccountInfo();
        if (!target_info.id.*.equals(target_info.owner_id.*)) {
            return error.InvalidKey;
        }
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
