# Anchor-Zig Benchmarks

This directory contains benchmark programs to measure CU (Compute Unit) consumption
of anchor-zig compared to other implementations.

## HelloWorld Benchmark

The simplest possible program - just logs "Hello world!".

### Results

| Implementation      | CU Usage | Overhead  | Size    |
|---------------------|----------|-----------|---------|
| Raw Zig (baseline)  | 105      | baseline  | 1.4 KB  |
| Anchor-Zig          | 131      | +26 CU    | 6.1 KB  |

### Reference (solana-program-rosetta)

| Implementation | CU Usage |
|----------------|----------|
| Rust           | 105      |
| Zig            | 105      |
| C              | 105      |
| Assembly       | 104      |

### Analysis

Anchor-Zig adds **26 CU overhead (24.8%)** for the framework infrastructure:
- Discriminator parsing (8 bytes)
- Instruction dispatch (u64 comparison)
- Context creation

This is a minimal overhead considering the features provided:
- Type-safe account handling
- Automatic discriminator validation
- Structured error handling
- IDL generation support

## Running Benchmarks

### Prerequisites

1. Solana CLI installed and configured
2. Local validator running (`solana-test-validator`)
3. Node.js and npm installed

### HelloWorld

```bash
cd benchmark/helloworld

# Build all implementations
../solana-zig/zig build -Drelease  # in each subdirectory

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

## Comparison Notes

### Why Anchor-Zig is efficient

1. **Compile-time computation** - Discriminators computed at compile time
2. **Fast validation** - u64 comparison instead of byte-by-byte
3. **Zero-copy access** - Direct pointer to account data
4. **Minimal runtime** - No allocator needed for basic operations

### Trade-offs

- **Size**: Programs are ~4x larger due to framework code
- **CU**: ~25% overhead for hello world (becomes negligible for complex programs)
- **Features**: Full Anchor-compatible IDL, type safety, constraints
