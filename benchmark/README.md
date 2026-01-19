# Anchor-Zig Benchmarks

This directory contains benchmark programs to measure CU (Compute Unit) consumption
of anchor-zig compared to other implementations.

## HelloWorld Benchmark

The simplest possible program - just logs "Hello world!".

### CU Overhead Analysis

| Implementation         | CU Usage | Delta    | Notes                          |
|-----------------------|----------|----------|--------------------------------|
| Raw Zig (baseline)    | 105      | -        | Just `sol_log_`                |
| Minimal (disc only)   | 125      | +20 CU   | Add discriminator check        |
| Anchor-Zig (full)     | 131      | +26 CU   | Full framework with Context    |

### Overhead Breakdown

```
Total overhead: +26 CU
├── Discriminator check: +20 CU (unavoidable - Anchor protocol)
└── Framework overhead:  +6 CU  (dispatch, context, error handling)
```

**The 20 CU discriminator overhead is inherent to the Anchor protocol** - any
Anchor-compatible program must read and compare 8 bytes of instruction data.

The actual framework overhead is only **6 CU**, which is extremely efficient!

### Reference (solana-program-rosetta)

| Implementation | CU Usage |
|----------------|----------|
| Rust           | 105      |
| Zig            | 105      |
| C              | 105      |
| Assembly       | 104      |

### Program Size Comparison

| Implementation    | Size     |
|-------------------|----------|
| Raw Zig           | 1.5 KB   |
| Minimal Anchor    | 2.3 KB   |
| Anchor-Zig (full) | 6.1 KB   |

The size difference comes from error handling, context management, and other
framework features that aren't used in the hello world path but are available
for more complex programs.

## Performance Tuning Options

### skip_length_check

For maximum performance when you're certain instruction data has at least 8 bytes:

```zig
return Entry.processInstruction(program_id, infos_slice, data, .{
    .skip_length_check = true,
});
```

Saves ~1 CU per instruction.

## Running Benchmarks

### Prerequisites

1. Solana CLI installed and configured
2. Local validator running (`solana-test-validator`)
3. Node.js and npm installed

### HelloWorld

```bash
cd benchmark/helloworld

# Build all implementations
for dir in zig-* anchor-*; do
  cd $dir && ../../solana-zig/zig build -Drelease && cd ..
done

# Run benchmark
npm install
npx tsx test_cu.ts
```

## Counter Benchmark (from main project)

More complex benchmark with state management and events.

| Operation   | CU Usage |
|-------------|----------|
| Initialize  | 479      |
| Increment   | 963      |

See `counter/` in the main project for the full implementation.

## Transfer Lamports Benchmark

Transfers lamports from one account to another with amount specified in instruction data.

### Results (after SDK optimization)

| Implementation     | CU Usage | Overhead  | Size     |
|--------------------|----------|-----------|----------|
| Raw Zig (baseline) | 38       | -         | 1.4 KB   |
| Anchor-Zig Opt     | 166      | +128 CU   | 6.2 KB   |
| Anchor-Zig         | 208      | +170 CU   | 7.8 KB   |

### Reference (solana-program-rosetta)

| Implementation | CU Usage |
|----------------|----------|
| Rust           | 459      |
| **Zig**        | **37**   |
| C              | 104      |
| Assembly       | 30       |
| Pinocchio      | 28       |

**Our Raw Zig now matches the rosetta baseline!** (38 vs 37 CU)

### SDK Fix

The original SDK used heap allocation for accounts array, adding ~57 CU overhead.
Fixed by using static [64]Account array (only 512 bytes on stack).

### Anchor-Zig Overhead Analysis

| Component                    | ~CU   |
|------------------------------|-------|
| Discriminator check          | 6     |
| accountsToInfoSlice (2 acct) | 20    |
| Borsh deserialization (u64)  | 10    |
| Account loading/validation   | 40    |
| Context creation             | 5     |
| Other framework code         | 47    |
| **Total**                    | ~128  |

Using `RawAccount` wrapper (optimized version) removes account validation overhead.

## Pubkey Comparison Benchmark

Compares account id with owner id (32 bytes comparison).

### Results

| Implementation     | CU Usage | Overhead  | Size     |
|--------------------|----------|-----------|----------|
| Raw Zig (baseline) | 5        | -         | 1.2 KB   |
| Anchor Ultra       | 18       | +13 CU    | 1.3 KB   |
| Anchor Standard    | 168      | +163 CU   | 7.9 KB   |

### Reference (solana-program-rosetta)

| Implementation | CU Usage |
|----------------|----------|
| Rust           | 14       |
| **Zig**        | **15**   |

**Our Raw Zig beats the rosetta reference!** (5 vs 15 CU)
**Anchor Ultra provides Anchor-compatible discriminator with only +13 CU overhead!**

### Overhead Analysis

| Layer                    | CU Cost |
|--------------------------|---------|
| Discriminator check      | +13 CU  |
| Context.load() parsing   | +26 CU  |
| ProgramEntry dispatch    | +113 CU |
| Account validation       | +11 CU  |

### Note on OptimizeMode

Using `ReleaseFast` instead of `ReleaseSmall` provides better CU performance:
- ReleaseSmall: 33 CU
- ReleaseFast: 5 CU

For CU-critical programs, use `ReleaseFast`.

## Summary

Anchor-Zig provides a full-featured, type-safe framework with:
- **Only 6 CU** of pure framework overhead (beyond Anchor protocol requirements)
- **26 CU total** overhead for HelloWorld (including unavoidable discriminator check)
- **77-118 CU** overhead for Transfer Lamports (depends on account validation)
- **~4-6 KB** additional program size for framework features

This makes anchor-zig one of the most efficient Anchor-compatible frameworks available.
