# 示例：PDA + Token CPI 完整链路

本示例展示：
- 使用 Typed DSL 定义 PDA 账户
- 初始化 PDA 作为 Token Account 的 authority
- 使用 `anchor.token.transferSigned` 执行 Token CPI

## 1. 标准流程脚本

建议使用一键脚本创建与同步项目：

```bash
./scripts/bootstrap-anchor-project.sh /path/to/project/pda_token_cpi pda_token_cpi
```

下文以 `/path/to/project/pda_token_cpi/` 为工作目录示例。

## 2. 账户与指令定义

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;
const dsl = anchor.dsl;

const VaultData = struct {
    authority: sol.PublicKey,
    bump: u8,
};

const TransferArgs = struct {
    amount: u64,
};

const TransferAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .authority = dsl.Signer,
    .vault = dsl.PDA(VaultData, .{
        .seeds = &.{ dsl.seed("vault"), dsl.seedFrom(.authority), dsl.seedBump(.vault) },
        .bump = true,
        .bump_field = "bump",
        .mut = true,
    }),
    .vault_ata = dsl.ATA(.{
        .mint = .mint,
        .authority = .vault,
        .init = true,
        .payer = .payer,
    }),
    .user_ata = dsl.Token(.{ .mint = .mint, .authority = .authority, .mut = true }),
    .mint = dsl.Mint(.{ .authority = .authority }),
    .token_program = dsl.TokenProgram,
    .system_program = dsl.SystemProgram,
    .associated_token_program = dsl.AssociatedTokenProgram,
});

const Transfer = dsl.Instr("vault_transfer", TransferAccounts, TransferArgs);

const Error = error{ TokenCpiFailed };
```

要点：
- `vault` 为 PDA 数据账户，保存 `authority` 与 `bump`
- `vault_ata` 由 PDA 作为 authority，必要时自动 init
- ATA init 需要 `token_program`、`system_program`、`associated_token_program`

## 3. 指令处理与 CPI 转账

```zig
pub fn vault_transfer(ctx: Transfer.Ctx, args: Transfer.Args) Error!void {
    const bump = ctx.accounts.vault.data.bump;
    const authority_key = ctx.accounts.authority.key().*;
    const authority_key_bytes = authority_key.bytes;

    const seeds = &.{
        &[_][]const u8{
            "vault",
            authority_key_bytes[0..],
            &.{ bump },
        },
    };

    if (anchor.token.transferSigned(
        ctx.accounts.token_program.toAccountInfo(),
        ctx.accounts.vault_ata.toAccountInfo(),
        ctx.accounts.user_ata.toAccountInfo(),
        ctx.accounts.vault.toAccountInfo(),
        args.amount,
        seeds,
    )) |err| {
        _ = err;
        return error.TokenCpiFailed;
    }
}
```

说明：
- `transferSigned` 需要与 PDA 派生一致的 `seeds`
- `authority_key_bytes` 请使用 SDK 提供的 PublicKey -> bytes API
- 账号顺序必须与 SPL Token CPI 要求一致

## 4. 构建与测试

```bash
./install-solana-zig.sh solana-zig
cd /path/to/project/pda_token_cpi
../solana-zig/zig build -Drelease
```

如需生成 IDL：

```bash
mkdir -p idl
../solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/pda_token_cpi.json
```
