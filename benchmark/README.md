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

## Summary

Anchor-Zig provides a full-featured, type-safe framework with:
- **Only 6 CU** of pure framework overhead (beyond Anchor protocol requirements)
- **26 CU total** overhead (including unavoidable discriminator check)
- **~4 KB** additional program size for framework features

This makes anchor-zig one of the most efficient Anchor-compatible frameworks available.
