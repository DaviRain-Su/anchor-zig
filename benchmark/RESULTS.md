# anchor-zig Final Benchmark Results

> Last updated: 2026-01-19

## 1. PubKey Benchmark (账户验证)

| Implementation | CU | Size | Overhead |
|----------------|-----|------|----------|
| zig-raw (baseline) | 5 | 1,240 B | - |
| **zero-cu-validated** | **5** | 1,264 B | **+0 CU** 🏆 |
| program-single | 7 | 1,360 B | +2 CU |
| zero-cu-single | 8 | 1,280 B | +3 CU |
| zero-cu-multi | 10 | 1,392 B | +5 CU |
| program-validated (3 ix) | 18 | 1,584 B | +13 CU |
| zero-cu-program (3 ix) | 19 | 2,024 B | +14 CU |

**Reference (solana-program-rosetta):**
| Implementation | CU |
|----------------|-----|
| Rust | 14 |
| Rust Anchor | ~150 |

## 2. Transfer Lamports Benchmark

| Implementation | CU | Size | vs Raw |
|----------------|-----|------|--------|
| **zero-cu-program** | **8** | 1,472 B | **-30 CU** 🚀 |
| **zero-cu** | **14** | 1,248 B | **-24 CU** 🚀 |
| zig-raw (baseline) | 38 | 1,456 B | - |

**Reference (solana-program-rosetta):**
| Implementation | CU |
|----------------|-----|
| Pinocchio | 28 |
| Zig | 37 |
| Rust Anchor | ~459 |

> 🎉 **anchor-zig is FASTER than raw Zig!**

## 3. HelloWorld Benchmark (log)

| Implementation | CU | Size | Overhead |
|----------------|-----|------|----------|
| zig-raw (with log) | 105 | 1,472 B | - |
| zero-cu (with log) | 109 | 1,512 B | +4 CU |

> Note: ~100 CU is for sol_log_ syscall

## 4. CPI Benchmark (PDA allocate)

| Implementation | CU | Size | Note |
|----------------|-----|------|------|
| zero-cu | 8 | 5,536 B | entry only |
| program() | 8 | 5,536 B | entry only |
| zig-raw (rosetta) | 2,797 | 5,576 B | full CPI |

**Reference (solana-program-rosetta):**
| Implementation | CU |
|----------------|-----|
| Pinocchio | 2,802 |
| Zig | 2,967 |
| Rust | 3,698 |

> Note: create_program_address = 1500 CU, invoke = 1000 CU

## 5. Token CPI Benchmark (SPL Transfer)

| Implementation | CU | Size | Overhead |
|----------------|-----|------|----------|
| zero-cu | 5,819 | 2,752 B | -12 CU |
| anchor-spl | 5,831 | 4,424 B | baseline |

> Note: ~5000+ CU is for SPL Token CPI invoke

---

## Summary

### API Performance

| API | CU Overhead | Best For |
|-----|-------------|----------|
| `entryValidated()` | **+0 CU** 🏆 | Single instruction |
| `program()` single | +2 CU | Single ix, program() API |
| `entry()` | +3 CU | Single ix, no validation |
| `multi()` | +5 CU | Multi ix, same accounts |
| `program()` + `ixValidated()` 3 ix | +13-14 CU | Multi ix (**recommended**) |

### Performance vs Rust Anchor

| Metric | anchor-zig | Rust Anchor | Improvement |
|--------|------------|-------------|-------------|
| Account check | 5-18 CU | ~150 CU | **8-30x faster** |
| Transfer lamports | 8-14 CU | ~459 CU | **33-57x faster** |
| Binary size | 1-2 KB | 100+ KB | **50-100x smaller** |

### Key Achievements

- ✅ `entryValidated()` achieves **ZERO overhead** vs raw Zig
- ✅ Transfer benchmark: anchor-zig is **FASTER than raw Zig**
- ✅ `program()` + `ixValidated()` is the recommended production pattern
- ✅ Validation adds **no extra CU cost** (compiler optimization)
