//! Anchor-Zig Transfer Lamports
//!
//! Transfers lamports from source account to destination account.
//! Uses anchor-zig framework with typed accounts and args.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

// Define transfer instruction args
const TransferArgs = struct {
    amount: u64,
};

// Use InterfaceAccountInfo for mutable account access
const TransferAccountInfo = anchor.InterfaceAccountInfo(.{ .mut = true });

// Define accounts struct
const TransferAccounts = struct {
    source: TransferAccountInfo,
    destination: TransferAccountInfo,
};

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("TransferLamports111111111111111111111111111");

    pub const instructions = struct {
        pub const transfer = anchor.Instruction(.{
            .Accounts = TransferAccounts,
            .Args = TransferArgs,
        });
    };

    pub fn transfer(ctx: anchor.Context(TransferAccounts), args: TransferArgs) !void {
        const source_info = ctx.accounts.source.toAccountInfo();
        const destination_info = ctx.accounts.destination.toAccountInfo();

        source_info.lamports.* -= args.amount;
        destination_info.lamports.* += args.amount;
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
