# sol-anchor-zig

Anchor-like framework for Solana program development in Zig.

## Quick Start

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const CounterData = struct {
    count: u64,
};

const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});

const InitializeAccounts = struct {
    payer: anchor.SignerMut,
    counter: Counter,
};

const InitializeArgs = struct {
    initial: u64,
};

const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
    };

    pub fn initialize(ctx: anchor.Context(InitializeAccounts), args: InitializeArgs) !void {
        ctx.accounts.counter.data.count = args.initial;
    }
};

pub fn processInstruction(
    program_id: *const sol.PublicKey,
    accounts: []const sol.account.Account.Info,
    data: []const u8,
) !void {
    try anchor.ProgramEntry(Program).dispatchWithConfig(program_id, accounts, data, .{});
}
```

## Typed DSL (No String Field Names)

```zig
const anchor = @import("sol_anchor_zig");
const dsl = anchor.dsl;

const CounterData = struct { count: u64 };
const InitializeArgs = struct { initial: u64 };

const InitializeAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .counter = dsl.Init(CounterData, .{ .payer = .payer, .name = "Counter" }),
});

const Initialize = dsl.Instr("initialize", InitializeAccounts, InitializeArgs);

pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
    ctx.accounts.counter.data.count = args.initial;
}
```

More details: `docs/README.md`

## Interface + CPI Helpers

```zig
const ProgramIds = [_]sol.PublicKey{
    sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    sol.PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
};

const InterfaceProgram = anchor.InterfaceProgram(ProgramIds[0..]);
const RawAccount = anchor.InterfaceAccountInfo(.{ .mut = true });

const Accounts = struct {
    authority: anchor.Signer,
    target_program: InterfaceProgram,
    remaining_account: RawAccount,
};

const Program = struct {
    pub const instructions = struct {
        pub const deposit = anchor.Instruction(.{
            .Accounts = Accounts,
            .Args = struct { amount: u64 },
        });
    };
};

var iface = try anchor.Interface(Program, .{ .program_ids = ProgramIds[0..] }).init(allocator, program_id);
const ix = try iface.instruction("deposit", accounts, .{ .amount = 1 });
defer ix.deinit();

const remaining = [_]*const sol.account.Account.Info{ &extra_info };
const ix_with_remaining = try iface.instructionWithRemaining("deposit", accounts, .{ .amount = 1 }, remaining[0..]);
defer ix_with_remaining.deinit();
```

Notes:
- Instruction builders return an `OwnedInstruction`; call `deinit()` when done.
- Interface CPI accounts accept `AccountMeta`, `AccountInfo`, or types with `toAccountInfo()`.
- Remaining accounts can be `[]AccountMeta` or `[]*const AccountInfo`.
- `anchor.Interface` provides `invoke` and `invokeSigned` helpers.
- Use `InterfaceConfig.meta_merge` if you need duplicate `AccountMeta` merging.

## Build + Test

```bash
./install-solana-zig.sh solana-zig
./solana-zig/zig build -Drelease
./solana-zig/zig build test --summary all
```

## Template

```bash
./scripts/new-anchor-project.sh /path/to/project project_name
./scripts/sync-template.sh /path/to/project
```

## IDL + Zig Client

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const MyProgram = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
    };
};

const idl_json = try anchor.generateIdlJson(allocator, MyProgram, .{});
const client_src = try anchor.generateZigClient(allocator, MyProgram, .{});
```

## IDL Output (Build Step)

```bash
./solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/my_program.json
```

`idl-program` must export `pub const Program`.

## Dependencies (build.zig.zon)

```zig
.dependencies = .{
    .solana_program_sdk = .{
        .url = "https://github.com/DaviRain-Su/solana-program-sdk-zig/archive/refs/heads/dev.tar.gz",
        .hash = "solana_program_sdk-0.17.1-wGj9UNYVHAD_uLlbUOhOAMLL08lQOXMm3Ss3Xw4VYvkt",
    },
    .sol_anchor_zig = .{
        .url = "https://github.com/DaviRain-Su/anchor-zig/archive/refs/heads/main.tar.gz",
        .hash = "sol_anchor_zig-0.1.0-xwtyYdpyCwCeBCQdaz4WPoX5ae63POhjg0BQC0wfehZ-",
    },
},
```

Fetch the latest hash with:

```bash
./solana-zig/zig fetch https://github.com/DaviRain-Su/anchor-zig/archive/refs/heads/main.tar.gz
```

## Example Project

The `counter/` project contains a minimal program and a TypeScript client:
- `counter/src/main.zig`
- `counter/client/src/index.ts`
