# sol-anchor-zig

High-performance Anchor-like framework for Solana program development in Zig.

## ⚡ Performance

| Implementation | CU Overhead | Binary Size |
|----------------|-------------|-------------|
| **zero_cu** | **5-7 CU** | ~1.3 KB |
| Standard Anchor | ~150 CU | ~7+ KB |
| Anchor Rust | ~150 CU | ~100+ KB |

**anchor-zig is 20-30x faster than Anchor Rust!**

## 🚀 Quick Start (Recommended: zero_cu API)

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

// Program ID
const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("YourProgramId111111111111111111111111111111");

// Account data structure
const CounterData = struct {
    count: u64,
    authority: sol.PublicKey,
};

// Define accounts with constraints
const IncrementAccounts = struct {
    authority: zero.Signer(0),                      // Must be signer
    counter: zero.Account(CounterData, .{          // Typed data access
        .owner = PROGRAM_ID,                        // Owner validation
    }),
};

// Instruction handler
pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
    ctx.accounts.counter.getMut().count += 1;
}

// Export (5 CU overhead!)
comptime {
    zero.entry(IncrementAccounts, "increment", increment);
}
```

## 📚 Account Types

```zig
const Accounts = struct {
    // Signer (must sign transaction, writable)
    authority: zero.Signer(0),
    
    // Mutable account with typed data
    counter: zero.Mut(CounterData),
    
    // Readonly account
    config: zero.Readonly(ConfigData),
    
    // Account with constraints
    vault: zero.Account(VaultData, .{
        .owner = PROGRAM_ID,
        .seeds = &.{ zero.seed("vault"), zero.seedAccount("authority") },
        .has_one = &.{"authority"},
    }),
};
```

## 🔧 Constraints

| Constraint | Syntax | Description |
|------------|--------|-------------|
| Owner | `.owner = PUBKEY` | Verify account owner |
| Address | `.address = PUBKEY` | Verify account address |
| Seeds (PDA) | `.seeds = &.{...}` | Verify PDA derivation |
| has_one | `.has_one = &.{"field"}` | Verify field matches account |
| Discriminator | `.discriminator = [8]u8` | Verify Anchor discriminator |

## 📤 Entry Points

```zig
// Single instruction (5 CU)
comptime {
    zero.entry(Accounts, "transfer", transfer_handler);
}

// With auto-validation
comptime {
    zero.entryValidated(Accounts, "transfer", transfer_handler);
}

// Multi-instruction (7 CU)
comptime {
    zero.multi(Accounts, .{
        zero.inst("initialize", init_handler),
        zero.inst("transfer", transfer_handler),
        zero.inst("close", close_handler),
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

## 📊 Complete Example

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;
const sol = anchor.sdk;

const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("Counter111111111111111111111111111111111111");

const CounterData = struct {
    count: u64,
    authority: sol.PublicKey,
    bump: u8,
};

// Initialize accounts
const InitAccounts = struct {
    payer: zero.Signer(0),
    authority: zero.Signer(0),
    counter: zero.Mut(CounterData),
};

// Increment accounts
const IncrementAccounts = struct {
    authority: zero.Signer(0),
    counter: zero.Account(CounterData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

pub const Program = struct {
    pub fn initialize(ctx: zero.Ctx(InitAccounts)) !void {
        // Write discriminator
        zero.writeDiscriminator(ctx.accounts.counter, "Counter");
        
        // Initialize data
        const data = ctx.accounts.counter.getMut();
        data.count = 0;
        data.authority = ctx.accounts.authority.id().*;
    }

    pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
        ctx.accounts.counter.getMut().count += 1;
    }
};

// Multi-instruction export
comptime {
    zero.multi(InitAccounts, .{
        zero.inst("initialize", Program.initialize),
    });
    zero.multi(IncrementAccounts, .{
        zero.inst("increment", Program.increment),
    });
}
```

## 📖 Standard API (Legacy)

For complex validation patterns or IDL generation, the standard API is still available:

```zig
const anchor = @import("sol_anchor_zig");

const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});

const Accounts = struct {
    payer: anchor.SignerMut,
    counter: Counter,
};

fn initialize(ctx: anchor.Context(Accounts)) !void {
    ctx.accounts.counter.data.count = 0;
}
```

## 🔗 Links

- [Benchmark Results](benchmark/README.md)
- [Feature Comparison](docs/FEATURE_COMPARISON.md)
- [CU Optimization Guide](docs/CU_OPTIMIZATION.md)
- [API Documentation](docs/README.md)

## 📦 Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .sol_anchor_zig = .{
        .url = "https://github.com/pichtranst123/anchor-zig/archive/main.tar.gz",
    },
},
```

## License

Apache 2.0
