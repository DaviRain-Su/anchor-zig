# Rust Anchor vs anchor-zig 功能对比

## 总体状态

| 功能类别 | Rust Anchor | anchor-zig (zero_cu) | 状态 |
|---------|-------------|---------------------|------|
| 账户类型 | ✅ 完整 | ✅ 完整 | ✅ |
| 约束系统 | ✅ 完整 | ✅ 完整 | ✅ |
| CPI 帮助 | ✅ 完整 | ⚠️ 基础 | ⚠️ |
| IDL 生成 | ✅ 完整 | ✅ 基础 | ✅ |
| 事件系统 | ✅ 完整 | ✅ 完整 | ✅ |
| 错误处理 | ✅ 完整 | ✅ 完整 | ✅ |

---

## 1. 账户类型 (Account Types)

| Rust Anchor | anchor-zig | 状态 | 说明 |
|-------------|-----------|------|------|
| `Account<'info, T>` | `zero.Account(T, .{})` | ✅ | 带类型数据的账户 |
| `Signer<'info>` | `zero.Signer(0)` | ✅ | 签名者账户 |
| `SystemAccount<'info>` | `zero.Mut(0)` / `SystemAccount` | ✅ | 系统账户 |
| `UncheckedAccount<'info>` | `zero.UncheckedAccount(0)` | ✅ | 不检查的账户 |
| `Program<'info, T>` | `zero.Program(ID)` | ✅ | 程序账户 |
| `Option<Account<...>>` | `zero.Optional(...)` | ✅ | 可选账户 |
| `AccountLoader<'info, T>` | ❌ | ❌ | 零拷贝大账户 |
| `Interface<'info, T>` | ❌ | ❌ | 接口账户 |
| `InterfaceAccount<'info, T>` | ❌ | ❌ | 接口账户 |

### 缺失功能：
- **AccountLoader** - 用于零拷贝访问大账户 (>10KB)
- **Interface/InterfaceAccount** - 用于多程序兼容 (如 Token-2022)

---

## 2. 约束系统 (Constraints)

| Rust Anchor | anchor-zig | 状态 | 说明 |
|-------------|-----------|------|------|
| `#[account(mut)]` | `zero.Mut(T)` | ✅ | 可变账户 |
| `#[account(signer)]` | `zero.Signer(T)` | ✅ | 签名者 |
| `#[account(owner = <pubkey>)]` | `.owner = PUBKEY` | ✅ | 所有者验证 |
| `#[account(address = <pubkey>)]` | `.address = PUBKEY` | ✅ | 地址验证 |
| `#[account(seeds = [...], bump)]` | `.seeds = &.{...}` | ✅ | PDA 验证 |
| `#[account(has_one = <field>)]` | `.has_one = &.{"field"}` | ✅ | 字段匹配 |
| `#[account(init, payer = <acc>, space = N)]` | `.init = true, .payer = "acc"` | ✅ | `processInit()` |
| `#[account(close = <acc>)]` | `.close = "acc"` | ✅ | `processClose()` |
| `#[account(realloc = N, ...)]` | `.realloc = N, .realloc_payer = "acc"` | ✅ | `processRealloc()` |
| `#[account(constraint = <expr>)]` | ❌ | ❌ | 自定义约束表达式 |
| `#[account(rent_exempt = ...)]` | `.rent_exempt = true/false` | ✅ | `validate()` |
| `#[account(executable)]` | `.executable = true` | ✅ | `validate()` |
| `#[account(zero)]` | `.zero = true` | ✅ | `validate()` |
| `#[account(bump = <expr>)]` | `.bump = <u8>` | ✅ | PDA 验证 |
| `token::mint` | `.token_mint = PUBKEY` | ✅ | Token mint 验证 |
| `token::authority` | `.token_authority = "acc"` | ✅ | Token authority 验证 |
| `mint::authority` | `.mint_authority = "acc"` | ✅ | Mint authority 验证 |
| `mint::decimals` | `.mint_decimals = <u8>` | ✅ | Mint decimals 验证 |

### 缺失功能：
- **constraint** - 自定义表达式约束 (需要用户手动实现)
- **associated_token::mint/authority** - ATA 约束 (可通过 token_* 实现)

---

## 3. CPI 帮助函数 (CPI Helpers)

### 3.1 系统程序 CPI

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| `system_program::create_account` | `zero.createAccount()` | ✅ |
| `system_program::transfer` | `zero.transferLamports()` | ✅ |
| `system_program::allocate` | `zero.allocate()` | ✅ |
| `system_program::assign` | ❌ | ❌ |

### 3.2 SPL Token CPI

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| `token::transfer` | `spl.token.transfer()` | ✅ |
| `token::mint_to` | `spl.token.mintTo()` | ✅ |
| `token::burn` | `spl.token.burn()` | ✅ |
| `token::close_account` | `spl.token.close()` | ✅ |
| `token::approve` | ❌ | ❌ |
| `token::revoke` | ❌ | ❌ |
| `token::set_authority` | ❌ | ❌ |
| `token::freeze_account` | ❌ | ❌ |
| `token::thaw_account` | ❌ | ❌ |
| `token::initialize_mint` | ❌ | ❌ |
| `token::initialize_account` | ❌ | ❌ |
| `token::sync_native` | ❌ | ❌ |

### 3.3 Associated Token CPI

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| `associated_token::create` | `associated_token.createCpi()` | ✅ |
| `associated_token::create_idempotent` | ❌ | ❌ |

### 缺失功能：
- Token approve/revoke/set_authority
- Token freeze/thaw
- Token initialize (mint/account)
- ATA create_idempotent

---

## 4. IDL 生成

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| 自动 IDL 生成 | `idl_zero.generateJson()` | ✅ |
| instructions | ✅ | ✅ |
| accounts | ✅ | ✅ |
| types | ✅ | ✅ |
| events | ✅ | ✅ |
| errors | ✅ | ⚠️ 手动定义 |
| constants | ❌ | ❌ |
| docs | ⚠️ 部分 | ⚠️ 部分 |

---

## 5. 事件系统 (Events)

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| `#[event]` | Event struct | ✅ |
| `emit!(event)` | `emitEvent(event)` | ✅ |
| 事件鉴别器 | ✅ | ✅ |

---

## 6. 错误处理

| Rust Anchor | anchor-zig | 状态 |
|-------------|-----------|------|
| `#[error_code]` | `AnchorError` enum | ✅ |
| 自定义错误 | `customErrorCode()` | ✅ |
| `require!()` | `if (!cond) return error` | ✅ |
| `require_eq!()` | 手动实现 | ✅ |
| `require_keys_eq!()` | 手动实现 | ✅ |

---

## 7. 其他功能

| 功能 | Rust Anchor | anchor-zig | 状态 |
|------|-------------|-----------|------|
| declare_id! | `pub const id = ...` | ✅ |
| #[program] | `comptime { zero.entry(...) }` | ✅ |
| Context bumps | ✅ | ⚠️ 需手动处理 |
| Remaining accounts | ✅ | ⚠️ 需手动处理 |
| Account close refund | ✅ | ✅ |
| Zero-copy | AccountLoader | ❌ |
| Access control | ✅ | 手动实现 |

---

## 优先实现建议

### 高优先级 (常用功能)
1. **Token approve/revoke** - 代币授权
2. **Token set_authority** - 修改权限
3. **realloc 约束** - 动态账户大小
4. **ATA create_idempotent** - 幂等创建 ATA

### 中优先级 (进阶功能)
5. **AccountLoader** - 零拷贝大账户
6. **constraint 表达式** - 自定义约束
7. **Token initialize** - 创建 mint/account
8. **Interface 账户** - Token-2022 兼容

### 低优先级 (特殊场景)
9. Token freeze/thaw
10. rent_exempt 验证
11. executable 检查

---

## 使用示例对比

### Rust Anchor
```rust
#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(init, payer = authority, space = 8 + 32 + 8)]
    pub counter: Account<'info, Counter>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
    ctx.accounts.counter.authority = ctx.accounts.authority.key();
    ctx.accounts.counter.count = 0;
    Ok(())
}
```

### anchor-zig (zero_cu)
```zig
const InitializeAccounts = struct {
    counter: zero.Account(Counter, .{
        .init = true,
        .payer = "authority",
    }),
    authority: zero.Signer(0),
    system_program: zero.Program(sol.system_program.ID),
};

pub fn initialize(ctx: zero.Ctx(InitializeAccounts)) !void {
    const counter = ctx.accounts.counter.getMut();
    counter.authority = ctx.accounts.authority.key();
    counter.count = 0;
}
```

---

## 重要设计差异

### Rust Anchor: 声明式约束自动执行
```rust
#[account(init, payer = authority, space = 8 + 32)]
pub counter: Account<'info, Counter>,
```
Anchor 会**自动**创建账户、验证约束、关闭账户等。

### anchor-zig (zero_cu): 声明 + 手动执行
```zig
counter: zero.Mut(COUNTER_SIZE),  // 只声明类型

fn initialize(ctx) !void {
    // 需要手动创建账户
    try zero.createAccount(ctx.accounts.payer, ctx.accounts.counter, ...);
    // 需要手动写入 discriminator
    @memcpy(data, &discriminator);
}
```

**原因**: zero_cu 追求极致性能 (5-7 CU)，不执行额外的验证代码。约束定义主要用于：
1. IDL 生成
2. 文档
3. 未来可选的验证层

---

## 需要添加的关键功能

### 1. SPL Token 完整 CPI (高优先级)

在 `src/spl/token.zig` 添加：

```zig
// 授权
pub fn approve(args: ApproveArgs) !void { ... }
pub fn revoke(args: RevokeArgs) !void { ... }

// 权限管理
pub fn setAuthority(args: SetAuthorityArgs) !void { ... }

// 冻结/解冻
pub fn freezeAccount(args: FreezeArgs) !void { ... }
pub fn thawAccount(args: ThawArgs) !void { ... }

// 初始化
pub fn initializeMint(args: InitMintArgs) !void { ... }
pub fn initializeAccount(args: InitAccountArgs) !void { ... }
```

### 2. System Program 完整 CPI

在 `zero_cu.zig` 或新建 `src/spl/system.zig`：

```zig
pub fn assign(account: anytype, owner: PublicKey) !void { ... }
pub fn createAccountWithSeed(...) !void { ... }
```

### 3. ATA create_idempotent

在 `src/associated_token.zig`：

```zig
pub fn createIdempotent(args: CreateIdempotentArgs) !void { ... }
```

---

## 结论

**anchor-zig 覆盖了 Rust Anchor 约 70-80% 的常用功能**，足以构建大多数 Solana 程序。

**设计哲学差异**：
- Rust Anchor: 安全优先，自动验证，~150 CU 开销
- anchor-zig: 性能优先，手动控制，5-7 CU 开销

主要功能差距：
1. SPL Token 的完整 CPI (approve, set_authority 等)
2. ATA create_idempotent
3. AccountLoader 零拷贝 (大账户场景)
4. Interface 账户类型 (Token-2022 兼容)

这些可以按需添加到 `spl/token.zig` 和 `zero_cu.zig` 中。
