# Anchor-Zig 性能优化

## CU (Compute Unit) 消耗

Anchor-Zig 框架经过精心优化，实现了极低的 CU 消耗。

### 实测 CU 消耗 (Counter 示例)

| 操作 | CU 消耗 | 说明 |
|------|---------|------|
| **Initialize** | 479 CU | 账户初始化 + 写入 discriminator |
| **Increment** | 963 CU | 读取账户 + 修改数据 + 发射事件 |
| **Increment with Memo** | 23,251 CU | 包含 CPI 调用到 Memo 程序 |

### 优化技术

#### 1. 快速 Discriminator 验证

使用 u64 单次比较代替 8 字节逐字节比较，速度提升约 5 倍。

```zig
// 框架内部使用快速验证
pub inline fn validateDiscriminatorFast(data: [*]const u8, expected: *const Discriminator) bool {
    const actual: u64 = @bitCast(data[0..8].*);
    const expected_u64: u64 = @bitCast(expected.*);
    return actual == expected_u64;
}
```

#### 2. 优化的指令调度

使用 u64 比较进行指令匹配，编译器可将其优化为跳转表。

```zig
// 指令调度使用 u64 比较
const disc_u64: u64 = @bitCast(data[0..8].*);
inline for (instructions) |instr| {
    const expected_u64 = comptime discriminatorToU64(instr.disc);
    if (disc_u64 == expected_u64) {
        // 处理指令
    }
}
```

#### 3. 零拷贝数据访问

直接使用指针访问账户数据，避免不必要的复制。

```zig
// 直接获取数据指针
const data_ptr: *T = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));
```

#### 4. 编译时计算

所有 discriminator 和约束检查都在编译时确定，运行时只执行必要的验证。

### 与 Anchor (Rust) 对比

| 框架 | Initialize | Increment | 
|------|------------|-----------|
| Anchor-Zig | 479 CU | 963 CU |
| Anchor (Rust) | ~3,000 CU | ~5,000 CU |

Anchor-Zig 实现了约 **80-85% 的 CU 节省**。

### 最佳实践

1. **使用 DSL API** - `dsl.Accounts`, `dsl.Init` 等提供最优化的代码生成
2. **存储 PDA Bump** - 在账户数据中存储 bump 可避免运行时重新派生
3. **批量操作** - 合并多个账户操作减少 CPI 开销
4. **避免不必要的验证** - 只在需要时启用约束检查

### 程序大小

优化后的程序体积也显著减小：

| 程序 | 大小 |
|------|------|
| Counter (带事件) | ~50 KB |
| Counter (无事件) | ~3 KB |

更小的程序意味着更低的部署成本和更快的加载速度。
