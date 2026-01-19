# anchor-zig 清理计划

## 概述

当前项目有两套 API：
1. **zero_cu** - 推荐的高性能 API (5-7 CU)
2. **Standard API** - 旧的 Anchor 风格 API (~150 CU)

本计划旨在清理旧的 Standard API，保留 zero_cu 核心功能。

## 模块分类

### ✅ 核心模块 (保留)

| 模块 | 行数 | 说明 |
|------|------|------|
| `zero_cu.zig` | 1419 | 核心 zero-CU API |
| `discriminator.zig` | 232 | 鉴别器计算 |
| `idl_zero.zig` | 720 | IDL 生成 |
| `idl_cli.zig` | 126 | IDL CLI 工具 |
| `error.zig` | 267 | 错误定义 |
| `spl/token.zig` | ~200 | SPL Token CPI |
| `spl/root.zig` | ~20 | SPL 入口 |
| `event.zig` | 223 | 事件发射 |

**总计: ~3,200 行**

### ⚠️ 需要评估的模块

| 模块 | 行数 | 说明 | 建议 |
|------|------|------|------|
| `pda.zig` | 346 | PDA 验证 | zero_cu 已有 PDA 支持，可能冗余 |
| `seeds.zig` | 552 | 种子规范 | zero_cu 已有种子定义 |
| `init.zig` | 506 | 账户初始化 | zero_cu 有 createAccount |
| `close.zig` | 407 | 账户关闭 | zero_cu 有 closeAccount |

### ❌ 旧 Standard API (可删除)

| 模块 | 行数 | 说明 |
|------|------|------|
| `account.zig` | 3691 | 旧的 Account wrapper |
| `constraints.zig` | 1906 | 旧的约束系统 |
| `typed_dsl.zig` | 1397 | 类型安全 DSL |
| `context.zig` | 1302 | 旧的 Context |
| `interface.zig` | 1250 | Interface CPI |
| `idl.zig` | 1259 | 旧 IDL 生成 |
| `token.zig` | 937 | 旧 Token (被 spl/token 替代) |
| `realloc.zig` | 660 | 重分配 |
| `cpi_context.zig` | 635 | CPI 上下文 |
| `stake.zig` | 603 | Stake |
| `attr.zig` | 443 | 属性 DSL |
| `signer.zig` | 301 | 旧 Signer |
| `program.zig` | 300 | 旧 Program |
| `program_entry.zig` | 269 | 程序入口 |
| `has_one.zig` | 267 | has_one 约束 |
| `codegen.zig` | 273 | 代码生成 |
| `lazy_account.zig` | 177 | LazyAccount |
| `sysvar_account.zig` | 173 | Sysvar |
| `associated_token.zig` | 154 | Associated Token |
| `optimized.zig` | 136 | 优化入口 |
| `account_loader.zig` | 129 | AccountLoader |
| `memo.zig` | 116 | Memo |
| `zero_program.zig` | 100 | 别名 |
| `system_account.zig` | 81 | SystemAccount |
| `idl_example.zig` | 9 | 示例 |

**总计: ~16,000+ 行可删除**

## 清理步骤

### Phase 1: 移动旧模块到 legacy 目录

```bash
mkdir -p src/legacy
mv src/account.zig src/legacy/
mv src/constraints.zig src/legacy/
mv src/typed_dsl.zig src/legacy/
mv src/context.zig src/legacy/
mv src/interface.zig src/legacy/
mv src/idl.zig src/legacy/
mv src/token.zig src/legacy/
# ... 等等
```

### Phase 2: 更新 root.zig

简化 `root.zig`，只导出 zero_cu 核心：

```zig
pub const zero_cu = @import("zero_cu.zig");
pub const discriminator = @import("discriminator.zig");
pub const idl = @import("idl_zero.zig");
pub const error_mod = @import("error.zig");
pub const spl = @import("spl/root.zig");
pub const event = @import("event.zig");
pub const sdk = @import("solana_program_sdk");

// 别名
pub const Signer = zero_cu.Signer;
pub const Mut = zero_cu.Mut;
pub const Readonly = zero_cu.Readonly;
pub const Account = zero_cu.Account;
pub const Program = zero_cu.Program;
pub const Ctx = zero_cu.Ctx;
// ... 等等
```

### Phase 3: 更新示例和文档

确保所有示例使用 zero_cu API。

### Phase 4: 删除 legacy 目录 (可选)

在确认没有人使用旧 API 后，删除 legacy 目录。

## 预期结果

- 代码量从 ~22,000 行减少到 ~5,000 行
- 更清晰的 API
- 更好的文档
- 更容易维护

## 问题

1. 是否需要保持向后兼容？
2. 是否需要在 legacy 目录保留旧 API？
3. zero_cu 是否缺少某些必要功能？
