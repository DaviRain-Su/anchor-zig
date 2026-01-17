# CPI 与 Interface 使用指南

本节介绍 `anchor.Interface`、CPI 指令构造与 `invoke`/`invokeSigned` 的常见用法。

## 1. InterfaceProgram 与账户类型

- `anchor.InterfaceProgram(program_ids)` 用于描述目标程序
- `anchor.InterfaceAccountInfo(.{ .mut = true })` 用于描述未包装的 AccountInfo

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
```

## 2. 构造指令

```zig
var iface = try anchor.Interface(Program, .{ .program_ids = ProgramIds[0..] }).init(allocator, program_id);
const ix = try iface.instruction("deposit", accounts, .{ .amount = 1 });
defer ix.deinit();
```

注意：
- `instruction()` 返回 `OwnedInstruction`，需要手动 `deinit()`
- Accounts 中可混用 `AccountMeta`、`AccountInfo` 或 `toAccountInfo()` 返回值

## 3. Remaining Accounts

```zig
const remaining = [_]*const sol.account.Account.Info{ &extra_info };
const ix_with_remaining = try iface.instructionWithRemaining(
    "deposit",
    accounts,
    .{ .amount = 1 },
    remaining[0..],
);
defer ix_with_remaining.deinit();
```

Remaining accounts 支持：
- `[]AccountMeta`
- `[]*const AccountInfo`

## 4. invoke / invokeSigned

`anchor.Interface` 提供 `invoke` 与 `invokeSigned`，用于在程序内 CPI 调用。

```zig
try iface.invoke("deposit", accounts, .{ .amount = 1 });

const seeds = &.{
    &[_][]const u8{ "vault", authority.key().bytes(), &.{ bump } },
};
try iface.invokeSigned("deposit", accounts, .{ .amount = 1 }, seeds);
```

## 5. 常见注意事项

- 对重复 `AccountMeta` 合并可使用 `InterfaceConfig.meta_merge`
- CPI 需要确保账户顺序与 IDL/指令定义一致
- 使用 PDA seeds 时，确保 bump 与 seeds 与账户地址匹配
