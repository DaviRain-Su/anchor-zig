# sol-anchor-zig

Anchor-like framework for Solana program development in Zig.

This package is extracted from `solana_program_sdk` and lives as a subpackage in the same repository. It depends on `solana_program_sdk` via a path dependency.

## Usage

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const CounterData = struct {
    count: u64,
    authority: sol.PublicKey,
};

const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});
```

## Project Template

Use the built-in template to scaffold a new Anchor-style program:

```bash
./scripts/new-anchor-project.sh /path/to/project project_name
```

To sync template updates into an existing project:

```bash
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

## Program Entry (Typed Dispatch)

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
    };

    pub fn initialize(ctx: anchor.Context(InitializeAccounts), args: InitializeArgs) !void {
        _ = ctx;
        _ = args;
    }

    pub fn fallback(ctx: anchor.FallbackContext) !void {
        _ = ctx;
    }
};

pub fn processInstruction(
    program_id: *const sol.PublicKey,
    accounts: []const sol.account.Account.Info,
    data: []const u8,
) !void {
    try anchor.ProgramEntry(Program).dispatchWithConfig(program_id, accounts, data, .{
        .fallback = Program.fallback,
    });
}
```

## Interface + CPI Helpers

```zig
const ProgramIds = [_]sol.PublicKey{
    sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    sol.PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
};

const InterfaceProgram = anchor.InterfaceProgram(ProgramIds[0..]);
const AnyProgram = anchor.InterfaceProgramAny;
const UncheckedProgram = anchor.InterfaceProgramUnchecked;
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
defer ix.deinit(allocator);

const remaining = [_]*const sol.account.Account.Info{ &extra_info };
const ix_with_remaining = try iface.instructionWithRemaining("deposit", accounts, .{ .amount = 1 }, remaining[0..]);
defer ix_with_remaining.deinit(allocator);
```

Interface CPI accounts accept `AccountMeta`, `AccountInfo`, or types with `toAccountInfo()`.
Remaining accounts can be provided as `[]AccountMeta` or `[]*const AccountInfo`.
Use `anchor.AccountMetaOverride` to override signer/writable flags when needed.
`anchor.Interface` provides `invoke`/`invokeSigned` helpers for CPI.
Interface account configs support `rent_exempt` to enforce rent exemption.
Use `InterfaceConfig.meta_merge` to merge duplicate AccountMeta entries when needed.

## IDL Output (Build Step)

```bash
cd anchor
../solana-zig/zig build idl \
  -Didl-program=../path/to/program.zig \
  -Didl-output=idl/my_program.json
```

`idl-program` must export `pub const Program`.

## Program Client

```zig
const client = @import("solana_client");
var rpc = client.RpcClient.init(allocator, "http://localhost:8899");
var program = ProgramClient.init(allocator, &rpc);

const sig = try program.sendInitialize(authority, payer, counter, args, &.{ &payer_kp, &authority_kp });
```

## Comptime Derives

```zig
const Accounts = anchor.Accounts(struct {
    authority: anchor.Signer,
    counter: anchor.Account(CounterData, .{
        .discriminator = anchor.accountDiscriminator("Counter"),
        .attrs = &.{
            anchor.attr.seeds(&.{ anchor.seed("counter"), anchor.seedAccount("authority") }),
            anchor.attr.bump(),
            anchor.attr.constraint("authority.key() == counter.authority"),
        },
    }),
});

const CounterLoader = anchor.AccountLoader(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});

const CounterLazy = anchor.LazyAccount(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});

const AccountsSugar = anchor.Accounts(struct {
    authority: anchor.Signer,
    counter: anchor.Account(CounterData, .{
        .discriminator = anchor.accountDiscriminator("Counter"),
        .attrs = anchor.attr.account(.{
            .seeds = &.{ anchor.seed("counter"), anchor.seedAccount("authority") },
            .seeds_program = anchor.seedAccount("authority"),
            .bump_field = "bump",
            .constraint = "authority.key() == counter.authority",
        }),
    }),
});

const AccountsTyped = anchor.Accounts(struct {
    authority: anchor.Signer,
    counter: anchor.Account(CounterData, .{
        .discriminator = anchor.accountDiscriminator("Counter"),
        .attrs = anchor.attr.account(.{
            .mut = true,
            .signer = true,
            .seeds = &.{ anchor.seed("counter"), anchor.seedAccount("authority") },
            .bump_field = "bump",
            .owner_expr = "authority.key()",
            .space_expr = "8 + INIT_SPACE",
            .constraint = "authority.key() == counter.authority",
        }),
    }),
});

const CounterTyped = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .bump_field = anchor.dataField(CounterData, .bump),
    .seeds = &.{
        anchor.seed("counter"),
        anchor.seedDataField(CounterData, .authority),
    },
});

const FieldAccounts = anchor.AccountsWith(struct {
    authority: anchor.Signer,
    counter: CounterTyped,
}, .{
    .counter = anchor.attr.account(.{
        .mut = true,
        .signer = true,
    }),
});

const FieldAccountsDerive = anchor.AccountsDerive(struct {
    authority: anchor.Signer,
    counter: CounterTyped,
    pub const attrs = .{
        .counter = anchor.attr.account(.{
            .mut = true,
            .signer = true,
        }),
    };
});

const CounterEvent = anchor.Event(struct {
    amount: anchor.eventField(u64, .{ .index = true }),
    owner: sol.PublicKey,
});
```

Indexed event fields must be `bool`, fixed-size integers (`u8/u16/u32/u64/u128/u256` and signed),
or `sol.PublicKey`. `usize/isize` are rejected to keep IDL stable across targets.

## Event Emission

Events are emitted via `sol_log_data` using Anchor's `[discriminator][borsh]` payload format.
You can emit events directly or through `Context.emit`.

```zig
const TransferEvent = anchor.Event(struct {
    from: sol.PublicKey,
    to: sol.PublicKey,
    amount: u64,
});

fn transfer(ctx: anchor.Context(TransferAccounts), amount: u64) !void {
    // ... transfer logic ...
    ctx.emit(TransferEvent, .{
        .from = ctx.accounts.from.key().*,
        .to = ctx.accounts.to.key().*,
        .amount = amount,
    });
}
```

## PDA Seed Dependencies

When seeds reference other accounts or account data fields, use
`loadAccountsWithDependencies` to resolve runtime seeds and validate PDAs.

```zig
const result = try anchor.loadAccountsWithDependencies(
    InitializeAccounts,
    program_id,
    accounts,
);
const ctx = anchor.Context(InitializeAccounts).new(
    result.accounts,
    program_id,
    &[_]sol.account.Account.Info{},
    result.bumps,
);
```

## Token Wrappers + CPI Helpers

Use the SPL Token wrappers for decoding token accounts and mint data, and
`anchor.token` CPI helpers to invoke the token program.

```zig
const token = anchor.token;

const TokenAccount = anchor.TokenAccount(.{});
const Mint = anchor.Mint(.{});

fn send(ctx: anchor.Context(TransferAccounts), amount: u64) !void {
    if (token.transfer(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.source.toAccountInfo(),
        ctx.accounts.destination.toAccountInfo(),
        ctx.accounts.authority.toAccountInfo(),
        amount,
    )) |err| switch (err) {
        .InvokeFailed => return error.InvokeFailed,
        .InvokeFailedWithCode => |code| {
            _ = code;
            return error.InvokeFailed;
        },
    };
}
```

When the mint is already loaded, use `transferCheckedWithMint` to avoid
passing decimals explicitly.

```zig
const token = anchor.token;

fn sendChecked(ctx: anchor.Context(TransferAccounts), amount: u64) !void {
    if (token.transferCheckedWithMint(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.source.toAccountInfo(),
        ctx.accounts.mint,
        ctx.accounts.destination.toAccountInfo(),
        ctx.accounts.authority.toAccountInfo(),
        amount,
    )) |err| switch (err) {
        .InvokeFailed => return error.InvokeFailed,
        .InvokeFailedWithCode => |code| {
            _ = code;
            return error.InvokeFailed;
        },
    };
}
```

For ATA init/payer semantics, use the ATA marker with `if_needed` (idempotent)
and include the associated token program and system program accounts.

```zig
const Accounts = anchor.typed.Accounts(.{
    .payer = anchor.typed.SignerMut,
    .authority = anchor.typed.Signer,
    .mint = anchor.typed.Mint(.{ .authority = .authority }),
    .ata = anchor.typed.ATA(.{
        .mint = .mint,
        .authority = .authority,
        .payer = .payer,
        .if_needed = true,
    }),
    .system_program = anchor.typed.SystemProgram,
    .token_program = anchor.typed.TokenProgram,
    .associated_token_program = anchor.typed.AssociatedTokenProgram,
});
```

## Batch Init Helpers

Use `anchor.createAccounts` to initialize multiple system accounts and
`anchor.associated_token.createBatchIdempotent` to create multiple ATAs.

```zig
try anchor.createAccounts(&[_]anchor.BatchInitConfig{
    .{
        .payer = ctx.accounts.payer.toAccountInfo(),
        .new_account = ctx.accounts.counter.toAccountInfo(),
        .owner = &program_id,
        .space = Counter.SPACE,
        .system_program = ctx.accounts.system_program.toAccountInfo(),
    },
    .{
        .payer = ctx.accounts.payer.toAccountInfo(),
        .new_account = ctx.accounts.vault.toAccountInfo(),
        .owner = &program_id,
        .space = Vault.SPACE,
        .system_program = ctx.accounts.system_program.toAccountInfo(),
    },
});

_ = anchor.associated_token.createBatchIdempotent(&[_]anchor.associated_token.BatchInitConfig{
    .{
        .associated_token_program = ctx.accounts.associated_token_program.toAccountInfo(),
        .payer = ctx.accounts.payer.toAccountInfo(),
        .associated_token_account = ctx.accounts.user_ata.toAccountInfo(),
        .authority = ctx.accounts.authority.toAccountInfo(),
        .mint = ctx.accounts.mint.toAccountInfo(),
        .system_program = ctx.accounts.system_program.toAccountInfo(),
        .token_program = ctx.accounts.token_program.toAccountInfo(),
    },
});
```

## Memo CPI Helper

Use `anchor.memo` to emit Memo program instructions from your program.

```zig
const memo = anchor.memo;

fn addMemo(ctx: anchor.Context(Accounts)) !void {
    try memo.memo(
        1,
        ctx.accounts.memo_program.toAccountInfo(),
        &[_]*const sol.account.Account.Info{ ctx.accounts.authority.toAccountInfo() },
        "hello",
        null,
    );
}
```

## Sysvar Data Wrappers

Use `SysvarData` aliases to parse common sysvars directly.

```zig
const Accounts = struct {
    clock: anchor.ClockData,
    rent: anchor.RentData,
    epoch_schedule: anchor.EpochScheduleData,
};
```

## CPI Context Builder

Use `CpiContext` to build and invoke CPI instructions with a fluent API.

```zig
const ctx = anchor.CpiContext(MyProgram, MyProgram.instructions.transfer.Accounts).init(
    allocator,
    ctx.accounts.target_program.toAccountInfo(),
    .{
        .from = ctx.accounts.from,
        .to = ctx.accounts.to,
        .authority = ctx.accounts.authority,
    },
);
const result = try ctx.invoke("transfer", .{ .amount = 1 });
_ = result;
```

Use inline remaining account helpers when you don't want to store them in the context.

```zig
const remaining = [_]*const sol.account.Account.Info{ ctx.accounts.extra.toAccountInfo() };
try ctx.invokeWithRemaining("transfer", .{ .amount = 1 }, remaining[0..]);
```

Collect remaining accounts incrementally, optionally using a pre-allocated pool.

```zig
var ctx = anchor.CpiContext(MyProgram, MyProgram.instructions.transfer.Accounts).init(
    allocator,
    ctx.accounts.target_program.toAccountInfo(),
    .{
        .from = ctx.accounts.from,
        .to = ctx.accounts.to,
        .authority = ctx.accounts.authority,
    },
);
defer ctx.deinit();

var remaining_pool: [4]sol.account.Account.Info = undefined;
ctx = ctx.withRemainingStorage(remaining_pool[0..]);
try ctx.appendRemaining(&[_]*const sol.account.Account.Info{ ctx.accounts.extra.toAccountInfo() });
try ctx.invoke("transfer", .{ .amount = 1 });
```

You can also clear and replace the remaining accounts in one call:

```zig
const remaining = [_]*const sol.account.Account.Info{ ctx.accounts.extra.toAccountInfo() };
try ctx.invokeWithRemainingReset("transfer", .{ .amount = 1 }, remaining[0..]);
```

When you need explicit signer seeds for a single call, use the signed reset helper.

```zig
const signer_seeds = &.{ &.{ "seed" } };
try ctx.invokeWithRemainingResetSigned("transfer", .{ .amount = 1 }, remaining[0..], signer_seeds);
```

## Constraint Expressions

Constraint expressions support arithmetic, comparisons, and string helpers.

```zig
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = anchor.constraint("clamp(counter.value, 0, 100) > 0 && contains(counter.label, \"ctr\")"),
});

const Accounts = anchor.Accounts(struct {
    authority: anchor.Signer,
    counter: Counter,
});
```

Case-insensitive helpers operate on ASCII bytes only.

```zig
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = anchor.constraint("starts_with_ci(counter.label, \"CTR\")"),
});
```

Typed constraint builder:

```zig
const c = anchor.constraint_typed;
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = c.field("label").startsWith("ctr").and_(
        c.field("count").add(c.int_(1)).eq(c.int_(3)),
    ),
});
```

Typed helpers for pubkey literals and explicit type assertions:

```zig
const c = anchor.constraint_typed;
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = c.field("authority")
        .eq(c.pubkey("11111111111111111111111111111111"))
        .and_(c.field("label").asBytes().len().eq(c.int_(3))),
});
```

You can also build pubkeys from compile-time PublicKey values:

```zig
const c = anchor.constraint_typed;
const program_id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = c.field("authority").eq(c.pubkey(program_id)),
});
```

Hex byte literal helper:

```zig
const c = anchor.constraint_typed;
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .constraint = c.field("label").eq(c.bytesFromHex("637472")),
});
```


## Stake Wrappers + CPI Helpers

Use `anchor.StakeAccount` to parse stake state and `anchor.stake` CPI helpers
to invoke the stake program.

```zig
const stake = anchor.stake;

fn deactivateStake(ctx: anchor.Context(Accounts)) !void {
    try stake.deactivate(
        ctx.accounts.stake_program.toAccountInfo(),
        ctx.accounts.stake_account.toAccountInfo(),
        ctx.accounts.clock_sysvar.toAccountInfo(),
        ctx.accounts.authority.toAccountInfo(),
        null,
    );
}
```

## AccountsDerive Auto Inference (Token/Mint/ATA)

AccountsDerive can auto-infer common token/mint/ata constraints when the
account data shape and field names match expected patterns.
It recognizes common aliases like `mint_account`, `token_mint_account`, and
`wallet`/`token_owner` for authority fields, and auto-wraps sysvars like `epoch_schedule`,
`recent_blockhashes`, and `fees` (including `sysvar_*` prefix), plus program aliases like `bpf_loader`,
`bpf_loader_upgradeable`, and `loader_v4`.
Associated token inference accepts either `owner` or `authority` fields in the
account data shape.
Associated token inference requires both `associated_token_program` and
`token_program` fields to be present in Accounts.
Cross-field constraints (token/mint/associated token refs) are validated at
comptime to ensure referenced Accounts fields exist and provide `key()`. Program
references (token_program/mint_token_program) are also checked to be Program or
UncheckedProgram fields.
The AccessFor owner reference must target a Program/UncheckedProgram field.
AccountsDerive also enforces that init/init_if_needed include a `system_program`
field, and token/mint/associated token constraints include the required
program fields (token_program/associated_token_program).
Payer/close/realloc targets are validated to ensure they expose `toAccountInfo()`
or are raw `AccountInfo` pointers.
Rent exemption is enforced at runtime when `rent_exempt` is set.
Common program aliases include `bpf_loader`, `bpf_loader_upgradeable`, `loader_v4`,
`compute_budget_program`, `address_lookup_table_program`, `ed25519_program`,
`secp256k1_program`, `secp256r1_program`, `vote_program`, and `feature_gate_program`.
Program auto binding applies to both `anchor.Program` and `anchor.UncheckedProgram` fields.

```zig
const TokenAccountData = struct {
    mint: sol.PublicKey,
    owner: sol.PublicKey,
};

const MintData = struct {
    mint_authority: sol.PublicKey,
    freeze_authority: sol.PublicKey,

    pub const DECIMALS: u8 = 6;
};

const TokenAccount = anchor.Account(TokenAccountData, .{
    .discriminator = anchor.accountDiscriminator("TokenAccount"),
});

const MintAccount = anchor.Account(MintData, .{
    .discriminator = anchor.accountDiscriminator("MintAccount"),
});

const AccountsAuto = anchor.AccountsDerive(struct {
    authority: anchor.Signer,
    token_mint: *const anchor.sdk.account.Account.Info,
    token_program: anchor.UncheckedProgram,
    ata_program: anchor.UncheckedProgram,
    token_account: TokenAccount,
    mint_account: MintAccount,
});
```

Supported aliases:

- token program: `token_program`, `spl_token_program`, `token_program_id`, `token_program_account`
- associated token program: `associated_token_program`, `associated_token_program_id`,
  `associated_token_program_account`, `ata_program`, `ata_program_id`
- token mint/authority: `mint` or `token_mint`, `authority` or `token_authority`
- token mint extended: `mint_pubkey`, `token_mint_pubkey`, `mint_key`, `token_mint_key`
- token mint extended: `mint_address`, `token_mint_address`, `mint_pk`, `token_mint_pk`
- token authority extended: `owner_pubkey`, `wallet_pubkey`, `authority_key`, `authority_address`,
  `owner_key`, `owner_address`, `wallet_address`

Constraint rules:

- `associated_token` cannot be combined with `token::*` or `mint::*` constraints.
- `token::*` constraints cannot be combined with `mint::*` constraints.
- `init`/`init_if_needed` validates account is writable and uninitialized; payer must be signer + writable.
- `executable` cannot be combined with `mut`, `signer`, `init`, `close`, or `realloc`.
- `zero` requires the discriminator bytes to be all zero.
- `space` enforces exact account data length when explicitly set.
- Duplicate mutable accounts are rejected unless the duplicated field uses `dup`.
- `token::mint/authority` validates the token account state and token program owner.
- `mint::authority/freeze_authority/decimals` validates the mint state and token program owner.
- `associated_token` validates the derived ATA address, token owner field, and token program owner.

## Build & Test

```bash
cd anchor
../solana-zig/zig build test --summary all
```
