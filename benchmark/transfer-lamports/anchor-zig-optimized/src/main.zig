//! Anchor-Zig Transfer Lamports - Optimized
//!
//! Uses raw AccountInfo pointers to skip all validation for maximum performance.

const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const TransferArgs = struct {
    amount: u64,
};

// Raw wrapper that stores AccountInfo pointer with no validation
const RawAccount = struct {
    info: *const sol.account.Account.Info,

    pub fn load(info: *const sol.account.Account.Info) !RawAccount {
        return .{ .info = info };
    }
};

// Define accounts struct with raw account type
const TransferAccounts = struct {
    source: RawAccount,
    destination: RawAccount,
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
        ctx.accounts.source.info.lamports.* -= args.amount;
        ctx.accounts.destination.info.lamports.* += args.amount;
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
    return Entry.processInstruction(program_id, infos_slice, data, .{
        .skip_length_check = true,
    });
}

comptime {
    sol.entrypoint(&processInstruction);
}
