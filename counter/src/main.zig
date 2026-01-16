const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;
const dsl = anchor.dsl;

const CounterData = struct {
    count: u64,
};

const InitializeArgs = struct {
    initial: u64,
};

const IncrementArgs = struct {
    amount: u64,
};

const InitializeAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .counter = dsl.Init(CounterData, .{ .payer = .payer, .name = "Counter" }),
});

const IncrementAccounts = dsl.Accounts(.{
    .authority = dsl.Signer,
    .counter = dsl.Data(CounterData, .{ .mut = true, .name = "Counter" }),
});

const Initialize = dsl.Instr("initialize", InitializeAccounts, InitializeArgs);
const Increment = dsl.Instr("increment", IncrementAccounts, IncrementArgs);

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("4ZfDpKj91bdUw8FuJBGvZu3a9Xis2Ce4QQsjMtwgMG3b");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = Initialize.Accs,
            .Args = Initialize.Args,
        });
        pub const increment = anchor.Instruction(.{
            .Accounts = Increment.Accs,
            .Args = Increment.Args,
        });
    };

    pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
        ctx.accounts.counter.data.count = args.initial;
    }

    pub fn increment(ctx: Increment.Ctx, args: Increment.Args) !void {
        ctx.accounts.counter.data.count += args.amount;
    }
};

fn processInstruction(
    program_id: *sol.PublicKey,
    accounts: []sol.Account,
    data: []const u8,
) sol.ProgramResult {
    const Entry = anchor.ProgramEntry(Program);
    var infos: [32]sol.account.Account.Info = undefined;
    const infos_slice = anchor.accountsToInfoSlice(accounts, infos[0..]);
    return Entry.processInstruction(program_id, infos_slice, data, .{});
}

comptime {
    sol.entrypoint(&processInstruction);
}
