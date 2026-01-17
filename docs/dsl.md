# Typed DSL 使用指南

本文覆盖 `anchor.dsl` 的主要能力：账户声明、指令定义、约束、Token/ATA、事件等。示例均为 Zig。

## 1. 基础结构

- `dsl.Accounts(.{ ... })` 生成账户类型
- `dsl.Instr(name, AccountsType, ArgsType)` 生成指令类型
- `Initialize.Ctx` 等价于 `anchor.Context(AccountsType)`

```zig
const anchor = @import("sol_anchor_zig");
const dsl = anchor.dsl;

const CounterData = struct { count: u64 };
const InitializeArgs = struct { initial: u64 };

const InitializeAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .counter = dsl.Init(CounterData, .{ .payer = .payer, .name = "Counter" }),
    .system_program = dsl.SystemProgram,
});

const Initialize = dsl.Instr("initialize", InitializeAccounts, InitializeArgs);

pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
    ctx.accounts.counter.data.count = args.initial;
}
```

## 2. 账户标记（Markers）

### 2.1 签名与基础账户

- `dsl.Signer` / `dsl.SignerMut`
- `dsl.Unchecked`
- `dsl.SystemAccount` / `dsl.SystemAccountMut`

### 2.2 Program 与 Sysvar

- Program: `dsl.Prog(program_id)`
- 常用 Program: `dsl.SystemProgram`、`dsl.TokenProgram`、`dsl.Token2022Program`、`dsl.AssociatedTokenProgram`、`dsl.MemoProgram`、`dsl.StakeProgram`、`dsl.ComputeBudgetProgram`、`dsl.AddressLookupTableProgram`
- 常用 Sysvar: `dsl.RentSysvar`、`dsl.ClockSysvar`、`dsl.EpochScheduleSysvar`、`dsl.InstructionsSysvar` 等

## 3. Data / Init / PDA / Close / Realloc

### 3.1 Data

```zig
.counter = dsl.Data(CounterData, .{
    .mut = true,
    .name = "Counter",
    .owner = .system_program,
    .constraint = dsl.constraint("counter.data.count >= 0"),
    .seeds = &.{ dsl.seed("counter"), dsl.seedFrom(.payer) },
    .bump = true,
})
```

### 3.2 Init

```zig
.counter = dsl.Init(CounterData, .{
    .payer = .payer,
    .name = "Counter",
    .space = 8 + @sizeOf(CounterData),
    .if_needed = false,
    .seeds = &.{ dsl.seed("counter"), dsl.seedFrom(.payer) },
    .bump = true,
})
```

- 必须提供 `payer`
- `space` 默认 = 8 + `@sizeOf(T)`
- `if_needed = true` 启用 `init_if_needed`

### 3.3 PDA

```zig
.pda = dsl.PDA(CounterData, .{
    .seeds = &.{ dsl.seed("counter"), dsl.seedFrom(.payer), dsl.seedBump(.bump) },
    .bump = true,
    .bump_field = "bump",
    .mut = true,
})
```

### 3.4 Close

```zig
.counter = dsl.Close(CounterData, .{ .destination = .payer, .name = "Counter" })
```

### 3.5 Realloc

```zig
.profile = dsl.Realloc(ProfileData, .{
    .payer = .payer,
    .space = 8 + @sizeOf(ProfileData),
    .zero_init = true,
})
```

## 4. Token / Mint / ATA / Stake

```zig
.token_account = dsl.Token(.{ .mint = .mint, .authority = .authority, .mut = true })
.mint = dsl.Mint(.{ .authority = .authority, .decimals = 9 })
.ata = dsl.ATA(.{ .mint = .mint, .authority = .authority, .init = true, .payer = .payer })
.stake = dsl.StakeAccount(.{ .mut = true, .signer = true })
```

ATA 初始化要求：
- 必须提供 `payer`
- `token_program`、`system_program`、`associated_token_program`/`ata_program` 必须存在
- `if_needed = true` 可进入 `init_if_needed`

## 5. Optional 与简写

```zig
.co_signer = dsl.Opt(dsl.Signer)
.config = dsl.Opt(dsl.Data(ConfigData, .{}))
```

快捷类型：
- `dsl.ReadOnly(T)` / `dsl.Mut(T)` / `dsl.MutPDA(T, seeds)`

## 6. Seeds 与 has_one

```zig
const seeds = &.{
    dsl.seed("vault"),
    dsl.seedFrom(.authority),
    dsl.seedData("nonce"),
    dsl.seedBump(.bump),
};

const has_one = dsl.hasOne(.authority);
const has_one_list = dsl.hasOneList(.{ .authority, .mint });
const has_one_target = dsl.hasOneTarget(.authority, .owner);
```

## 7. 事件

```zig
const TransferEvent = anchor.dsl.Event(.{
    .from = anchor.sdk.PublicKey,
    .to = anchor.sdk.PublicKey,
    .amount = anchor.dsl.eventField(u64, .{ .index = true }),
});

pub fn transfer(ctx: anchor.Context(Accounts), amount: u64) !void {
    ctx.emit(TransferEvent, .{
        .from = ctx.accounts.from.key().*,
        .to = ctx.accounts.to.key().*,
        .amount = amount,
    });
}
```

## 8. 账户属性 DSL（宏风格）

```zig
const Constrained = anchor.Account(Data, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .attrs = anchor.attr.account(.{
        .mut = true,
        .signer = true,
        .seeds = &.{ anchor.dsl.seed("counter") },
        .bump_field = "bump",
        .init = true,
        .payer = "payer",
        .has_one_fields = &.{ "authority" },
        .close = "destination",
        .realloc = .{ .payer = "payer", .zero_init = true },
        .rent_exempt = true,
        .constraint = "authority.key() == counter.authority",
        .owner_expr = "program.key()",
        .address_expr = "expected.key()",
        .space_expr = "8 + INIT_SPACE",
    }),
});
```

适用于需要与 Anchor 约束语义对齐的场景。

## 9. 更多示例

- `docs/example-counter.md`
- `docs/example-pda-token-cpi.md`
- `docs/example-ata-mint-transfer.md`
