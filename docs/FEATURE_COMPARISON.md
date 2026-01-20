# Feature Comparison: zero_cu vs Standard Anchor

## Overview

| Feature | zero_cu | Standard Anchor | Notes |
|---------|---------|-----------------|-------|
| **CU Overhead** | **5-18 CU** | ~150 CU | zero_cu is 8-30x faster |
| **Binary Size** | ~1.2-2 KB | ~100+ KB | zero_cu is 50-100x smaller |
| **Constraints** | ✅ Declarative | ✅ Declarative | Same API style |

## Benchmark Results

### PubKey (Account Check)

| Implementation | CU | Size | Notes |
|----------------|-----|------|-------|
| Raw Zig | 5 | 1,240 B | Baseline |
| zero-cu-validated | 5 | 1,264 B | **ZERO overhead!** |
| program-single | 7 | 1,360 B | +2 CU |
| zero-cu-single | 8 | 1,280 B | +3 CU |
| zero-cu-multi | 10 | 1,392 B | +5 CU |
| program-validated | 18 | 1,584 B | +13 CU (multi instruction) |
| Rust Anchor | ~150 | 100+ KB | Full validation |

### Transfer Lamports

| Implementation | CU | Size | Notes |
|----------------|-----|------|-------|
| zero-cu-program | 8 | 1,472 B | 🚀 **Faster than raw!** |
| zero-cu | 14 | 1,248 B | 🚀 **Faster than raw!** |
| Raw Zig | 38 | 1,456 B | Baseline |
| Rust Anchor | ~459 | 100+ KB | 33-57x slower |

## Account Features

| Feature | zero_cu | Standard Anchor | How to migrate |
|---------|---------|-----------------|----------------|
| Signer check | ✅ `isSigner()` | ✅ auto | Manual check in handler |
| Writable check | ✅ `isWritable()` | ✅ `.mut = true` | Manual check in handler |
| Typed data access | ✅ `get()`, `getMut()` | ✅ `.data` | Same |
| Account pubkey | ✅ `id()` | ✅ `key()` | Same |
| Account owner | ✅ `ownerId()` | ✅ `owner()` | Same |
| Lamports | ✅ `lamports()` | ✅ `lamports()` | Same |
| Raw data | ✅ `data()`, `dataMut()` | ✅ `rawData()` | Same |

## Validation Features

| Feature | zero_cu | Standard Anchor | Notes |
|---------|---------|-----------------|-------|
| Discriminator check | ✅ Auto (8-byte) | ✅ Auto | Same |
| Owner validation | ✅ `verifyOwner()` | ✅ `.owner` | Manual call |
| Address validation | ✅ `verifyAddress()` | ✅ `.address` | Manual call |
| Signer validation | ✅ `verifySigner()` | ✅ `.signer` | Manual call |
| Mut validation | ✅ `verifyWritable()` | ✅ `.mut` | Manual call |
| Executable check | ✅ `verifyExecutable()` | ✅ `.executable` | Manual call |
| Data length check | ✅ `verifyDataLen()` | ✅ `.space` | Manual call |
| Min lamports check | ✅ `verifyMinLamports()` | ❌ | Manual call |
| Batch signer check | ✅ `ctx.verifySigners()` | ✅ Auto | One call |
| Batch writable check | ✅ `ctx.verifyWritable()` | ✅ Auto | One call |

## Advanced Features

| Feature | zero_cu | Standard Anchor | Notes |
|---------|---------|-----------------|-------|
| PDA validation | ✅ `.seeds` | ✅ `.seeds` | Auto in `ctx.validate()` |
| PDA bump storage | ❌ Manual | ✅ `.bump` | Store manually |
| Account init | ✅ `.init` | ✅ `.init` | Comptime flag |
| Account close | ✅ `.close` | ✅ `.close` | Comptime flag |
| has_one constraint | ✅ `.has_one` | ✅ `.has_one` | Auto in `ctx.validate()` |
| Discriminator | ✅ `.discriminator` | ✅ Auto | Optional |
| Token constraints | ❌ Manual | ✅ `.token_*` | Use SPL directly |
| Associated token | ❌ Manual | ✅ `.associated_token` | Use ATA directly |
| Events | ❌ Manual | ✅ `emitEvent()` | Use `sol.log.log()` |
| IDL generation | ❌ | ✅ `generateIdlJson()` | Manual IDL |
| CPI helpers | ❌ | ✅ `Interface` | Use SDK directly |

## Code Examples

### Signer Validation

**Standard Anchor:**
```zig
const Accounts = struct {
    authority: anchor.Signer,  // Auto-validated
};
```

**zero_cu:**
```zig
const Accounts = struct {
    authority: zero.Signer(0),
};

pub fn handler(ctx: zero.Ctx(Accounts)) !void {
    if (!ctx.accounts.authority.isSigner()) {
        return error.MissingSigner;
    }
}
```

### Owner Validation

**Standard Anchor:**
```zig
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .owner = PROGRAM_ID,  // Auto-validated
});
```

**zero_cu:**
```zig
const Accounts = struct {
    counter: zero.Mut(CounterData),
};

pub fn handler(ctx: zero.Ctx(Accounts)) !void {
    if (!ctx.accounts.counter.ownerId().equals(PROGRAM_ID)) {
        return error.InvalidOwner;
    }
}
```

### PDA Validation

**Standard Anchor:**
```zig
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .seeds = &.{ anchor.seed("counter"), anchor.seedAccount("authority") },
});
```

**zero_cu:**
```zig
pub fn handler(ctx: zero.Ctx(Accounts)) !void {
    const expected = sol.PublicKey.findProgramAddress(
        .{ "counter", &ctx.accounts.authority.id().bytes },
        &PROGRAM_ID,
    ) catch return error.InvalidPDA;
    
    if (!ctx.accounts.counter.id().equals(expected.address)) {
        return error.InvalidPDA;
    }
}
```

### Account Initialization

**Standard Anchor:**
```zig
const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
    .init = true,
    .payer = "payer",
    .space = 8 + @sizeOf(CounterData),
});
```

**zero_cu:**
```zig
pub fn initialize(ctx: zero.Ctx(Accounts)) !void {
    // Create account via CPI
    const space = 8 + @sizeOf(CounterData);
    const lamports = sol.rent.minimumBalance(space);
    
    sol.system_program.createAccount(
        ctx.accounts.payer,
        ctx.accounts.counter,
        lamports,
        space,
        &PROGRAM_ID,
    );
    
    // Write discriminator
    const disc = anchor.accountDiscriminator("Counter");
    @memcpy(ctx.accounts.counter.dataMut(8), &disc);
    
    // Initialize data
    ctx.accounts.counter.getMut().count = 0;
}
```

## When to Use Each

### Use zero_cu when:
- ✅ CU optimization is critical (DeFi, high-frequency)
- ✅ You want Anchor-style declarative constraints
- ✅ You want smallest binary size (50-100x smaller than Rust)
- ✅ Performance matters (8-30x faster than Rust Anchor)

### Use Standard Anchor when:
- ✅ You need PDA validation
- ✅ You need account initialization
- ✅ You need complex constraints (has_one, close, realloc)
- ✅ You need IDL generation for clients
- ✅ Safety is more important than performance
- ✅ You need CPI helpers

## Migration Strategy

1. **Start with Standard Anchor** for development
2. **Profile CU usage** in production
3. **Migrate hot paths to zero_cu** if needed
4. **Keep complex logic in Standard Anchor**

## Hybrid Approach

You can use both in the same program:

```zig
// Recommended: use program() + ixValidated() for multi-instruction (18 CU)
comptime {
    zero.program(.{
        zero.ixValidated("transfer", TransferAccounts, transfer),
        zero.ixValidated("close", CloseAccounts, close),
    });
}

// Complex path: use standard Anchor
pub fn initialize(ctx: anchor.Context(InitAccounts)) !void {
    // Uses full validation, PDA, init
}
```
