# anchor-zig CU Benchmarks

Benchmarks comparing CU (Compute Unit) consumption across different implementations.
Test logic matches [solana-program-rosetta](https://github.com/solana-developers/solana-program-rosetta).

## Results Summary

### 1. PubKey Benchmark (id == owner check)

Compares account ownership verification performance.

| Implementation | CU | Binary Size | Overhead | API |
|----------------|-----|-------------|----------|-----|
| zig-raw (baseline) | 5 | 1,240 B | - | Raw Zig |
| **zero-cu-single** | **5** | 1,280 B | **+0 CU** | `entry()` |
| zero-cu-validated | 5 | 1,264 B | +0 CU | `entryValidated()` |
| **zero-cu-multi** | **7** | 1,392 B | **+2 CU** | `multi()` |
| zero-cu-program-single | 19 | 1,360 B | +14 CU | `program()` single ix |
| zero-cu-program-validated | 18 | 1,584 B | +13 CU | `program()` + validated |
| zero-cu-program | 19 | 2,024 B | +14 CU | `program()` multi ix |

**Reference (solana-program-rosetta):**
| Implementation | CU |
|----------------|-----|
| Rust | 14 |
| Zig | 15 |

**anchor-zig `entry()` is 3x faster than rosetta!**

---

### 2. HelloWorld Benchmark (logging)

Compares program logging overhead.

| Implementation | CU | Binary Size | Description |
|----------------|-----|-------------|-------------|
| zig-raw | ~100 | 1,472 B | Raw Zig with sol_log |
| zero-cu-raw | ~100 | 1,472 B | zero_cu raw entry |
| zero-cu | ~100 | 1,512 B | `entry()` API |
| zero-cu-program | ~100 | 1,512 B | `program()` API |

*Note: CU mainly consumed by sol_log syscall (~100 CU per log)*

---

### 3. Transfer Lamports Benchmark

Compares lamport transfer between accounts.

| Implementation | CU | Binary Size | Description |
|----------------|-----|-------------|-------------|
| zig-raw (baseline) | 37 | 1,456 B | Raw pointer manipulation |
| **zero-cu** | **37** | 1,248 B | **`entry()` - ZERO overhead!** |
| zero-cu-program | 55 | 1,472 B | `program()` API |

**Reference (solana-program-rosetta):**
| Implementation | CU |
|----------------|-----|
| Rust | 102 |
| Zig | 39 |

**anchor-zig matches raw Zig performance!**

---

### 4. CPI Benchmark (System Program allocate)

Compares Cross-Program Invocation overhead.

| Implementation | CU | Binary Size | Description |
|----------------|-----|-------------|-------------|
| zig-raw | ~1,200 | 5,576 B | Raw Zig CPI |
| zero-cu | ~1,200 | 5,656 B | `program()` API |
| zero-cu-anchor | ~1,200 | 5,656 B | Anchor-style |

*Note: CU mainly consumed by system program allocate syscall*

---

### 5. SPL Token Benchmark

Compares SPL Token operations (transfer, mint, burn).

| Implementation | CU | Binary Size | Description |
|----------------|-----|-------------|-------------|
| zig-raw | varies | 6,944 B | Raw token operations |
| zero-cu | varies | 6,768 B | `program()` API |
| anchor-spl | varies | 5,912 B | Using anchor-spl lib |

---

### 6. Token CPI Benchmark

Compares SPL Token CPI operations.

| Implementation | CU | Binary Size | Description |
|----------------|-----|-------------|-------------|
| zero-cu | varies | 2,752 B | zero_cu token CPI |
| anchor-spl | varies | 4,424 B | anchor-spl CPI |

**zero-cu is 38% smaller than anchor-spl!**

---

## API Performance Summary

| API | CU Overhead | Best For |
|-----|-------------|----------|
| `entry()` | +0 CU | Single instruction, max performance |
| `entryValidated()` | +0 CU | Single instruction + constraints |
| `multi()` | +2 CU | Multiple instructions, same account layout |
| `program()` | +14-18 CU | Different account layouts (most flexible) |

---

## Comparison with Rust Anchor

| Operation | anchor-zig | Rust Anchor | Improvement |
|-----------|------------|-------------|-------------|
| Account check | 5 CU | ~150 CU | **30x faster** |
| Transfer lamports | 37 CU | ~150 CU | **4x faster** |
| Binary size | 1-7 KB | 100+ KB | **15-100x smaller** |

---

## Running Benchmarks

```bash
# Start local validator
solana-test-validator

# Build all programs
cd benchmark/pubkey
for dir in zig-raw zero-cu-*; do
    (cd $dir && ../../solana-zig/zig build)
done

# Run CU tests
npm install
npx tsx test_cu.ts
```

## Directory Structure

```
benchmark/
├── pubkey/                         # Account ownership check
│   ├── zig-raw/                   # Baseline (5 CU)
│   ├── zero-cu-single/            # entry() (5 CU)
│   ├── zero-cu-multi/             # multi() (7 CU)
│   ├── zero-cu-validated/         # entryValidated() (5 CU)
│   ├── zero-cu-program/           # program() (19 CU)
│   ├── zero-cu-program-single/    # program() single (19 CU)
│   ├── zero-cu-program-validated/ # program() validated (18 CU)
│   └── test_cu.ts
│
├── helloworld/                    # Logging benchmark
│   ├── zig-raw/
│   ├── zero-cu/
│   ├── zero-cu-raw/
│   ├── zero-cu-program/
│   └── test_cu.ts
│
├── transfer-lamports/             # Lamport transfer
│   ├── zig-raw/                   # (37 CU)
│   ├── zero-cu/                   # (37 CU)
│   ├── zero-cu-program/           # (55 CU)
│   └── test_cu.ts
│
├── cpi/                           # CPI benchmark
│   ├── zig-raw/
│   ├── zero-cu/
│   ├── zero-cu-anchor/
│   └── test_cu.ts
│
├── token/                         # SPL Token operations
│   ├── zig-raw/
│   ├── zero-cu/
│   ├── anchor-spl/
│   └── test_cu.ts
│
├── token-cpi/                     # Token CPI
│   ├── zero-cu/
│   ├── anchor-spl/
│   └── test_cu.ts
│
└── solana-zig/                    # Solana Zig compiler
```
