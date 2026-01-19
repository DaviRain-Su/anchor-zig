# anchor-zig CU Benchmarks

Benchmarks comparing CU (Compute Unit) consumption across different implementations.
Test logic matches [solana-program-rosetta](https://github.com/solana-developers/solana-program-rosetta).

## Results Summary

### pubkey Benchmark (id == owner check)

| Implementation      | CU  | Size    | Overhead   |
|---------------------|-----|---------|------------|
| zig-raw (baseline)  | 5   | 1240 B  | baseline   |
| **zero-cu-single**  | **5** | 1280 B | **ZERO!** |
| **zero-cu-multi**   | **7** | 1392 B | **+2 CU** |

### Reference (solana-program-rosetta)

| Implementation | CU  |
|----------------|-----|
| Rust           | 14  |
| Zig            | 15  |

**anchor-zig is 3x faster than rosetta!**

## zero_cu API

The `zero_cu` module provides high-level abstractions with zero runtime overhead.
All offsets are computed at compile time.

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

// Define accounts with sizes
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

// Single instruction (5 CU)
comptime { zero.entry(Accounts, "check", check); }

// Multi-instruction (7 CU each)
comptime {
    zero.multi(Accounts, .{
        zero.inst("check", check),
        zero.inst("verify", verify),
    });
}
```

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build all variants
cd benchmark/pubkey
for dir in zig-raw zero-cu-single zero-cu-multi; do
    (cd $dir && ../../solana-zig/zig build)
done

# Run CU tests
npx tsx test_cu.ts
```

## Directory Structure

```
benchmark/
├── pubkey/                    # id == owner comparison
│   ├── zig-raw/              # Raw Zig baseline
│   ├── zero-cu-single/       # zero_cu single instruction
│   ├── zero-cu-multi/        # zero_cu multi-instruction
│   └── test_cu.ts            # CU measurement script
├── helloworld/               # Hello world logging
└── transfer-lamports/        # Lamport transfer
```
