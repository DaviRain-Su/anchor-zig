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
| **fast-single**     | **5** | 1272 B | **ZERO!** |
| **fast-multi**      | **7** | 1384 B | **+2 CU** |

### Reference (solana-program-rosetta)

| Implementation | CU  |
|----------------|-----|
| Rust           | 14  |
| Zig            | 15  |

**anchor-zig is 3x faster than rosetta!**

## API Comparison

### anchor.fast (Recommended)

Anchor-style patterns with ZeroCU performance:

```zig
const fast = anchor.fast;

const Accounts = struct {
    authority: fast.Signer,
    counter: fast.Account(CounterData),
};

pub fn increment(ctx: fast.Context(Accounts)) !void {
    ctx.accounts.counter.getMut().count += 1;
}

// Single (5 CU)
comptime { fast.exportSingle(Accounts, "increment", increment); }

// Multi (7 CU)
comptime {
    fast.exportProgram(Accounts, .{
        fast.instruction("init", init),
        fast.instruction("increment", increment),
    });
}
```

### zero_cu (Low-level)

Direct offset calculation with explicit sizes:

```zig
const zero = anchor.zero_cu;

const Accounts = struct {
    target: zero.Readonly(1),
};

comptime { zero.entry(Accounts, "check", Program.check); }
```

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build all variants
cd benchmark/pubkey
for dir in zig-raw zero-cu-single zero-cu-multi fast-single fast-multi; do
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
│   ├── fast-single/          # anchor.fast single
│   ├── fast-multi/           # anchor.fast multi
│   └── test_cu.ts            # CU measurement script
├── helloworld/               # Hello world logging
└── transfer-lamports/        # Lamport transfer
```
