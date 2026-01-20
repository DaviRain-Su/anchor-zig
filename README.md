# sol-anchor-zig

High-performance Anchor-like framework for Solana program development in Zig.

## ⚡ Performance

### CU Benchmark Results

| Benchmark | zig-raw | anchor-zig | Rust Anchor | Improvement |
|-----------|---------|------------|-------------|-------------|
| Account check | 5 CU | **5-18 CU** | ~150 CU | **8-30x faster** |
| Transfer lamports | 38 CU | **8-14 CU** 🚀 | ~459 CU | **33-57x faster** |
| Multi-instruction | N/A | **18 CU** | ~150 CU | **8x faster** |

### API Comparison

| API | CU Overhead | Binary Size | Use Case |
|-----|-------------|-------------|----------|
| `entryValidated()` | **+0 CU** | ~1.3 KB | Single instruction + auto constraints |
| `entry()` | +3 CU | ~1.3 KB | Single instruction, no validation |
| `multi()` | +5 CU | ~1.4 KB | Multiple instructions, same accounts |
| `program()` + `ixValidated()` | **+13-14 CU** | ~1.6-2 KB | Different account layouts ✨ **Recommended** |
| Rust Anchor | ~150 CU | 100+ KB | - |

**anchor-zig achieves zero overhead with `entryValidated()` and 8x faster than Rust with `program()`!**

### Binary Size Comparison

| Implementation | Size |
|----------------|------|
| anchor-zig (entry) | 1.2-1.5 KB |
| anchor-zig (program) | 1.6-2.0 KB |
| Raw Zig | 1.2-1.5 KB |
| Rust Anchor | 100+ KB |

**anchor-zig is 50-100x smaller than Rust Anchor!**

See [benchmark/README.md](benchmark/README.md) for detailed results.

## 🚀 Quick Start (Recommended Pattern)

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const idl = anchor.idl_zero;
const sol = anchor.sdk;

// Program ID
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("YourProgram11111111111111111111111111111111");

// ============================================================================
// Account Data
// ============================================================================

const CounterData = struct {
    count: u64,
    authority: sol.PublicKey,
};

// ============================================================================
// Instruction Accounts (each can have different layout)
// ============================================================================

const InitializeAccounts = struct {
    payer: zero.Signer(0),
    counter: zero.Mut(CounterData),
    system_program: zero.Readonly(0),
};

const IncrementAccounts = struct {
    authority: zero.Signer(0),
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},  // Auto-validated!
    }),
};

const CloseAccounts = struct {
    authority: zero.Signer(0),
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
    destination: zero.Mut(0),
};

// ============================================================================
// Handlers
// ============================================================================

pub fn initialize(ctx: zero.Ctx(InitializeAccounts)) !void {
    zero.writeDiscriminator(ctx.accounts.counter, "Counter");
    const data = ctx.accounts.counter.getMut();
    data.count = 0;
    data.authority = ctx.accounts.payer.id().*;
}

pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    ctx.accounts.counter.getMut().count += 1;
}

pub fn close(ctx: zero.Ctx(CloseAccounts)) !void {
    try zero.closeAccount(ctx.accounts.counter, ctx.accounts.destination);
}

// ============================================================================
// Program Entry (RECOMMENDED)
// ============================================================================

comptime {
    zero.program(.{
        zero.ixValidated("initialize", InitializeAccounts, initialize),
        zero.ixValidated("increment", IncrementAccounts, increment),
        zero.ixValidated("close", CloseAccounts, close),
    });
}
```

## 📚 Account Types

```zig
const Accounts = struct {
    // Signer (must sign, writable)
    authority: zero.Signer(0),
    
    // Mutable account with typed data
    counter: zero.Mut(CounterData),
    
    // Readonly account
    config: zero.Readonly(ConfigData),
    
    // Account with constraints (auto-validated)
    vault: zero.Account(VaultData, .{
        .owner = PROGRAM_ID,
        .seeds = &.{ zero.seed("vault"), zero.seedAccount("authority") },
        .has_one = &.{"authority"},
    }),
    
    // Optional account
    optional_config: zero.Optional(zero.Readonly(ConfigData)),
    
    // Program account
    system_program: zero.Program(sol.system_program.id),
};
```

## 🔧 Constraints

| Constraint | Syntax | Description |
|------------|--------|-------------|
| owner | `.owner = PUBKEY` | Verify account owner |
| address | `.address = PUBKEY` | Verify account address |
| seeds (PDA) | `.seeds = &.{...}` | Verify PDA derivation |
| has_one | `.has_one = &.{"field"}` | Verify field matches account |
| discriminator | `.discriminator = [8]u8` | Verify Anchor discriminator |

## 📤 Entry Points

```zig
// RECOMMENDED: Different account layouts per instruction
comptime {
    zero.program(.{
        zero.ixValidated("init", InitAccounts, init),
        zero.ixValidated("process", ProcessAccounts, process),
        zero.ixValidated("close", CloseAccounts, close),
    });
}

// Alternative: Single instruction (5 CU, max performance)
comptime { zero.entry(Accounts, "transfer", transfer); }

// Alternative: Same account layout (7 CU)
comptime {
    zero.multi(Accounts, .{
        zero.inst("deposit", deposit),
        zero.inst("withdraw", withdraw),
    });
}
```

## 🛠 CPI Helpers

```zig
// Create account
try zero.createAccount(ctx.accounts.payer, ctx.accounts.new_account, space, owner);

// Transfer lamports
try zero.transferLamports(ctx.accounts.from, ctx.accounts.to, amount);

// Close account
try zero.closeAccount(ctx.accounts.closeable, ctx.accounts.destination);

// Get rent exempt balance
const lamports = zero.rentExemptBalance(space);

// Write discriminator
zero.writeDiscriminator(ctx.accounts.account, "AccountName");
```

## 📊 IDL Generation

```zig
// Define program metadata for IDL
pub const Program = struct {
    pub const id = PROGRAM_ID;
    pub const name = "my_program";
    pub const version = "0.1.0";

    pub const instructions = .{
        idl.InstructionWithDocs("initialize", InitAccounts, InitArgs, "Initialize account"),
        idl.InstructionWithDocs("process", ProcessAccounts, void, "Process data"),
    };

    pub const accounts = .{
        idl.AccountDefWithDocs("MyAccount", MyData, "Account description"),
    };

    pub const errors = enum(u32) {
        InvalidInput = 6000,
    };
};

// Generate IDL JSON
const json = try idl.generateJson(allocator, Program);
```

## 📦 Project Template

Use our template for new projects:

```bash
cp -r template/program my_program
cd my_program
# Edit src/main.zig, build.zig.zon
../path/to/solana-zig/zig build
```

See [template/program/README.md](template/program/README.md) for details.

## 🔗 Links

- [Benchmark Results](benchmark/README.md)
- [Feature Comparison](docs/FEATURE_COMPARISON.md)
- [Project Template](template/program/)

## 📦 Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .solana_program_sdk = .{
        .path = "path/to/solana-program-sdk-zig",
    },
    .sol_anchor_zig = .{
        .path = "path/to/anchor-zig",
    },
},
```

## License

Apache 2.0
