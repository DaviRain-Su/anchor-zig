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
| optimized-minimal   | 31  | 1528 B  | +26 CU     |

### Reference (solana-program-rosetta)

| Implementation | CU  |
|----------------|-----|
| Rust           | 14  |
| Zig            | 15  |

**Our ZeroCU is 3x faster than rosetta!**

## API Tiers

### 1. ZeroCU (5-7 CU)

Zero runtime overhead with Anchor-style abstractions:

```zig
const zero = anchor.zero_cu;

const Accounts = struct {
    target: zero.Readonly(1),  // 1 byte data
};

pub fn check(ctx: zero.Ctx(Accounts)) !void {
    if (!ctx.accounts.target.id().equals(ctx.accounts.target.ownerId().*)) {
        return error.InvalidKey;
    }
}

// Single instruction (5 CU)
comptime { zero.entry(Accounts, "check", Program.check); }

// Multi-instruction (7 CU)
comptime {
    zero.multi(Accounts, .{
        zero.inst("check", Program.check),
        zero.inst("verify", Program.verify),
    });
}
```

### 2. Optimized Entry (31+ CU)

Standard Anchor API with tiered validation:

```zig
pub const Program = struct {
    pub const instructions = struct {
        pub const check = anchor.Instruction(.{ .Accounts = MyAccounts });
    };
    pub fn check(ctx: anchor.Context(MyAccounts)) !void { ... }
};

comptime {
    anchor.optimized.exportEntrypoint(Program, .minimal);
}
```

| Level     | Checks                    | CU Overhead |
|-----------|---------------------------|-------------|
| full      | All Anchor constraints    | ~150 CU     |
| minimal   | Discriminator + signer    | ~31 CU      |
| unchecked | Discriminator only        | ~10 CU      |

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build all variants
cd benchmark/pubkey
for dir in zig-raw zero-cu-single zero-cu-multi optimized-minimal; do
    (cd $dir && ../../solana-zig/zig build)
done

# Deploy and test
npx tsx test_cu.ts
```

## Directory Structure

```
benchmark/
├── pubkey/                    # id == owner comparison
│   ├── zig-raw/              # Raw Zig baseline
│   ├── zero-cu-single/       # ZeroCU single instruction
│   ├── zero-cu-multi/        # ZeroCU multi-instruction
│   ├── optimized-minimal/    # Standard Anchor (minimal)
│   └── test_cu.ts            # CU measurement script
├── helloworld/               # Hello world logging
└── transfer-lamports/        # Lamport transfer
```
