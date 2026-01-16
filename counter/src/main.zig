const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const CounterData = struct {
    count: u64,
};

const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .mut = true,
});

const InitCounter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .mut = true,
    .init = true,
    .payer = "payer",
});

const InitializeAccounts = struct {
    payer: anchor.SignerMut,
    counter: InitCounter,
};

const InitializeArgs = struct {
    initial: u64,
};

const IncrementAccounts = struct {
    authority: anchor.Signer,
    counter: Counter,
};

const IncrementArgs = struct {
    amount: u64,
};

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("4ZfDpKj91bdUw8FuJBGvZu3a9Xis2Ce4QQsjMtwgMG3b");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
        pub const increment = anchor.Instruction(.{
            .Accounts = IncrementAccounts,
            .Args = IncrementArgs,
        });
    };

    pub fn initialize(ctx: anchor.Context(InitializeAccounts), args: InitializeArgs) !void {
        ctx.accounts.counter.data.count = args.initial;
    }

    pub fn increment(ctx: anchor.Context(IncrementAccounts), args: IncrementArgs) !void {
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
