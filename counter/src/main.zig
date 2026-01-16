const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;
const dsl = anchor.dsl;
const memo = anchor.memo;

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

const IncrementWithMemoAccounts = dsl.Accounts(.{
    .authority = dsl.Signer,
    .counter = dsl.Data(CounterData, .{ .mut = true, .name = "Counter" }),
    .memo_program = dsl.MemoProgram,
});

const Initialize = dsl.Instr("initialize", InitializeAccounts, InitializeArgs);
const Increment = dsl.Instr("increment", IncrementAccounts, IncrementArgs);
const IncrementWithMemo = dsl.Instr("increment_with_memo", IncrementWithMemoAccounts, IncrementArgs);

pub const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("4ZfDpKj91bdUw8FuJBGvZu3a9Xis2Ce4QQsjMtwgMG3b");

    pub const events = struct {
        pub const CounterEvent = struct {
            authority: sol.PublicKey,
            amount: u64,
            count: u64,
        };
    };

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = Initialize.Accs,
            .Args = Initialize.Args,
        });
        pub const increment = anchor.Instruction(.{
            .Accounts = Increment.Accs,
            .Args = Increment.Args,
        });
        pub const increment_with_memo = anchor.Instruction(.{
            .Accounts = IncrementWithMemo.Accs,
            .Args = IncrementWithMemo.Args,
        });
    };

    pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
        ctx.accounts.counter.data.count = args.initial;
    }

    pub fn increment(ctx: Increment.Ctx, args: Increment.Args) !void {
        ctx.accounts.counter.data.count += args.amount;
        ctx.emit(events.CounterEvent, .{
            .authority = ctx.accounts.authority.key().*,
            .amount = args.amount,
            .count = ctx.accounts.counter.data.count,
        });
    }

    pub fn increment_with_memo(ctx: IncrementWithMemo.Ctx, args: IncrementWithMemo.Args) !void {
        ctx.accounts.counter.data.count += args.amount;
        ctx.emit(events.CounterEvent, .{
            .authority = ctx.accounts.authority.key().*,
            .amount = args.amount,
            .count = ctx.accounts.counter.data.count,
        });

        try memo.memo(
            1,
            ctx.accounts.memo_program.toAccountInfo(),
            &[_]*const sol.account.Account.Info{ctx.accounts.authority.toAccountInfo()},
            "counter increment",
            null,
        );
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
