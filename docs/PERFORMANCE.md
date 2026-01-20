# Anchor-Zig 性能优化

## CU (Compute Unit) 消耗

Anchor-Zig 框架经过精心优化，实现了极低的 CU 消耗。

### 基准测试结果

#### PubKey Benchmark (账户验证)

| 实现 | CU | 二进制大小 | 开销 |
|------|-----|-----------|------|
| zig-raw (baseline) | 5 | 1,240 B | - |
| **zero-cu-validated** | **5** | 1,264 B | **+0 CU** |
| program-single | 7 | 1,360 B | +2 CU |
| zero-cu-single | 8 | 1,280 B | +3 CU |
| zero-cu-multi | 10 | 1,392 B | +5 CU |
| **program-validated** | **18** | 1,584 B | **+13 CU** |
| zero-cu-program | 19 | 2,024 B | +14 CU |

#### Transfer Lamports Benchmark

| 实现 | CU | 二进制大小 | 说明 |
|------|-----|-----------|------|
| **zero-cu-program** | **8** | 1,472 B | 🚀 比 raw 更快！ |
| **zero-cu** | **14** | 1,248 B | 🚀 比 raw 更快！ |
| zig-raw (baseline) | 38 | 1,456 B | - |
| Rust Anchor | ~459 | 100+ KB | 33-57x 更慢 |

### API 性能对比

| API | CU 开销 | 最佳场景 |
|-----|---------|----------|
| `entryValidated()` | **+0 CU** | 单指令 + 约束 (极致性能) |
| `program()` single | +2 CU | 单指令使用 `program()` API |
| `entry()` | +3 CU | 单指令，无验证 |
| `multi()` | +5 CU | 多指令，相同账户布局 |
| `program()` + `ixValidated()` | **+13-14 CU** | 多指令 (推荐通用模式) ✨ |

### 与 Rust Anchor 对比

| 操作 | anchor-zig | Rust Anchor | 提升 |
|------|------------|-------------|------|
| 账户验证 | 5-18 CU | ~150 CU | **8-30x 更快** |
| Lamport 转账 | 8-14 CU | ~459 CU | **33-57x 更快** |
| 二进制大小 | 1-2 KB | 100+ KB | **50-100x 更小** |

### 优化技术

#### 1. 静态偏移计算

对于已知数据大小的账户，在编译时计算偏移量，避免运行时遍历：

```zig
// 编译时计算指令数据偏移
const IX_DATA_OFFSET = comptime instructionDataOffset(&.{ 
    accountSize(@sizeOf(CounterData)),  // counter
    accountSize(0),                       // authority (Signer)
});
```

#### 2. 延迟 Context 加载

只在需要动态解析时才加载完整 Context，静态账户直接使用预计算偏移：

```zig
// 先尝试静态路径（更快）
inline for (handlers) |H| {
    if (!needsDynamicParsing(H.AccountsType)) {
        // 直接使用静态偏移访问 discriminator
        const disc_ptr: *align(1) const u64 = @ptrCast(input + H.ix_data_offset);
        if (disc_ptr.* == H.discriminator) {
            return H.load(input).handle();
        }
    }
}
// 只有必要时才加载完整 context
const context = Context.load(input);
```

#### 3. is_fixed_size 标记

区分"无数据账户"和"未知大小账户"，让 `Signer(0)` 等类型也能使用静态路径：

```zig
pub fn Signer(comptime DataOrLen: anytype) type {
    return struct {
        pub const data_size = 0;
        pub const is_fixed_size = true;  // 关键！即使 data_size=0 也是固定大小
    };
}
```

#### 4. 快速 Discriminator 验证

使用 u64 单次比较代替 8 字节逐字节比较：

```zig
const actual: *align(1) const u64 = @ptrCast(data.ptr);
const expected: u64 = comptime @bitCast(disc);
return actual.* == expected;
```

#### 5. 零拷贝数据访问

直接使用指针访问账户数据，避免复制：

```zig
pub fn get(self: Self) *const T {
    return @ptrCast(@alignCast(self.account.data().ptr + 8));
}
```

### 最佳实践

1. **使用 `program()` + `ixValidated()`** - 推荐的通用模式，18 CU 开销
2. **使用 `entryValidated()`** - 极致性能场景，0 CU 开销
3. **声明固定账户大小** - 使用 `Signer(0)` 而非外部账户类型
4. **避免 `Program` 类型** - 它需要动态解析，增加 CU

### 程序大小

| 实现 | 大小 |
|------|------|
| anchor-zig (entry) | 1.2-1.5 KB |
| anchor-zig (program) | 1.6-2.0 KB |
| Raw Zig | 1.2-1.5 KB |
| Rust Anchor | 100+ KB |

**anchor-zig 比 Rust Anchor 小 50-100 倍！**

更小的程序意味着更低的部署成本和更快的加载速度。
