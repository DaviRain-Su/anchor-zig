# anchor-zig CU Benchmarks

Benchmarks comparing CU (Compute Unit) consumption across different implementations.
Test logic matches [solana-program-rosetta](https://github.com/solana-developers/solana-program-rosetta).

## Results Summary

### pubkey Benchmark (id == owner check)

| Implementation      | CU  | Size    | Overhead   | Use Case |
|---------------------|-----|---------|------------|----------|
| zig-raw (baseline)  | 5   | 1240 B  | baseline   | - |
| **zero-cu-single**  | **5** | 1280 B | **ZERO!** | Single instruction |
| **zero-cu-multi**   | **7** | 1392 B | **+2 CU** | Same account layout |
| zero-cu-validated   | 5   | 1264 B  | ZERO!      | With constraints |
| **zero-cu-program** | **19** | 1664 B | **+14 CU** | Different layouts |

### Reference (solana-program-rosetta)

| Implementation | CU  |
|----------------|-----|
| Rust           | 14  |
| Zig            | 15  |

**anchor-zig zero-cu is 3x faster than rosetta!**

## API Comparison

| API | CU | Binary Size | When to Use |
|-----|-----|-------------|-------------|
| `entry()` | 5 | ~1.3 KB | Single instruction, max performance |
| `multi()` | 7 | ~1.4 KB | Multiple instructions, same accounts |
| `program()` | 19 | ~1.7 KB | Different account layouts per instruction |

## zero_cu API

The `zero_cu` module provides high-level abstractions with zero runtime overhead.
All offsets are computed at compile time.

### entry() - Single Instruction (5 CU)

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

const Accounts = struct {
    authority: zero.Signer(0),
    target: zero.Readonly(1),
};

pub fn check(ctx: zero.Ctx(Accounts)) !void {
    const target = ctx.accounts.target;
    if (!target.id().equals(target.ownerId().*)) {
        return error.InvalidKey;
    }
}

comptime { zero.entry(Accounts, "check", check); }
```

### multi() - Same Account Layout (7 CU)

```zig
comptime {
    zero.multi(Accounts, .{
        zero.inst("check", check),
        zero.inst("verify", verify),
    });
}
```

### program() - Different Account Layouts (19 CU)

```zig
const InitAccounts = struct {
    payer: zero.Signer(0),
    counter: zero.Mut(CounterData),
};

const IncrementAccounts = struct {
    authority: zero.Signer(0),
    counter: zero.Account(CounterData, .{ .owner = PROGRAM_ID }),
};

comptime {
    zero.program(.{
        zero.ix("initialize", InitAccounts, initialize),
        zero.ix("increment", IncrementAccounts, increment),
    });
}
```

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build all variants
cd benchmark/pubkey
for dir in zig-raw zero-cu-single zero-cu-multi zero-cu-validated zero-cu-program; do
    (cd $dir && ../../solana-zig/zig build)
done

# Run CU tests
npx tsx test_cu.ts
```

## Directory Structure

```
benchmark/
├── pubkey/                    # id == owner comparison
│   ├── zig-raw/              # Raw Zig baseline (5 CU)
│   ├── zero-cu-single/       # entry() API (5 CU)
│   ├── zero-cu-multi/        # multi() API (7 CU)
│   ├── zero-cu-validated/    # With constraints (5 CU)
│   ├── zero-cu-program/      # program() API (19 CU)
│   └── test_cu.ts            # CU measurement script
├── helloworld/               # Hello world logging
└── transfer-lamports/        # Lamport transfer
```
