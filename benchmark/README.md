# Anchor-Zig CU Benchmarks

Benchmarks comparing CU (Compute Unit) consumption across different implementations.

## Summary

| Implementation     | CU Usage | Overhead   | Size     |
|--------------------|----------|------------|----------|
| Raw Zig            | 5        | baseline   | 1.2 KB   |
| **ZeroCU Single**  | **5**    | **0 CU**   | 1.3 KB   |
| **ZeroCU Multi**   | **7**    | **+2 CU**  | 1.3 KB   |
| Anchor Standard    | 168      | +163 CU    | 7.9 KB   |

### Reference (solana-program-rosetta)

| Implementation | CU Usage |
|----------------|----------|
| Rust           | 14       |
| Zig            | 15       |

**Our ZeroCU is 3x faster than rosetta!**

## ZeroCU Framework

The `zero_cu` module provides Anchor-style abstractions with zero runtime overhead.
All calculations done at compile time.

### Single Instruction (5 CU)

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

const MyAccounts = struct {
    target: zero.Readonly(1),  // Account with 1 byte data
};

pub const Program = struct {
    pub fn check(ctx: zero.Ctx(MyAccounts)) !void {
        const target = ctx.accounts.target;  // Named access!
        
        if (!target.id().equals(target.ownerId().*)) {
            return error.InvalidKey;
        }
    }
};

// Single-line export!
comptime {
    zero.entry(MyAccounts, "check", Program.check);
}
```

### Multi-Instruction (7 CU each)

```zig
const SharedAccounts = struct {
    authority: zero.Signer(0),
    target: zero.Mut(8),
};

pub const Program = struct {
    pub fn initialize(ctx: zero.Ctx(SharedAccounts)) !void { ... }
    pub fn increment(ctx: zero.Ctx(SharedAccounts)) !void { ... }
    pub fn close(ctx: zero.Ctx(SharedAccounts)) !void { ... }
};

comptime {
    zero.multi(SharedAccounts, .{
        zero.inst("initialize", Program.initialize),
        zero.inst("increment", Program.increment),
        zero.inst("close", Program.close),
    });
}
```

## Key Optimizations

1. **Comptime offset calculation** - All account offsets computed at compile time
2. **u64 discriminator comparison** - Single instruction compare instead of memcmp
3. **Precomputed discriminators** - SHA256 hashes computed at compile time
4. **No heap allocation** - All data accessed via stack pointers
5. **ReleaseFast optimization** - Use `.ReleaseFast` for best CU performance

## Account Type Markers

| Type | Description |
|------|-------------|
| `zero.Signer(data_len)` | Must be transaction signer, writable |
| `zero.Mut(data_len)` | Writable account |
| `zero.Readonly(data_len)` | Read-only account |

The `data_len` parameter specifies the account's data size in bytes.
This is required for comptime offset calculation.

## Benchmarks

### HelloWorld
- Raw Zig: 105 CU
- Anchor-Zig: 131 CU (+26 CU)

### Transfer Lamports  
- Raw Zig: 38 CU
- Anchor-Zig: 166-208 CU (+128-170 CU)

### Pubkey Comparison
- Raw Zig: 5 CU
- ZeroCU: 5 CU (0 overhead!)
- Anchor Standard: 168 CU

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build programs
cd benchmark/pubkey/zig-raw && ../../solana-zig/zig build
cd benchmark/pubkey/anchor-zig-unified && ../../solana-zig/zig build

# Run tests
cd benchmark/pubkey && npm install && npx tsx test_cu.ts
```
