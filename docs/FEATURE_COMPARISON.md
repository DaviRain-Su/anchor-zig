# Feature Comparison: zero_cu vs Standard Anchor

## Overview

| Feature | zero_cu | Standard Anchor | Notes |
|---------|---------|-----------------|-------|
| **CU Overhead** | **5-7 CU** | ~150 CU | zero_cu is 20-30x faster |
| **Binary Size** | ~1.3 KB | ~7+ KB | zero_cu is 5x smaller |

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

| Feature | zero_cu | Standard Anchor | Migration Path |
|---------|---------|-----------------|----------------|
| PDA validation | ❌ | ✅ `.seeds` | Use `sol.PublicKey.findProgramAddress()` |
| PDA bump storage | ❌ | ✅ `.bump` | Store manually |
| Account init | ❌ | ✅ `.init` | Use CPI to system program |
| Account close | ❌ | ✅ `.close` | Manual lamport transfer |
| Account realloc | ❌ | ✅ `.realloc` | Use `account.realloc()` |
| has_one constraint | ❌ | ✅ `.has_one` | Manual comparison |
| Token constraints | ❌ | ✅ `.token_*` | Use SPL token directly |
| Associated token | ❌ | ✅ `.associated_token` | Use ATA program |
| Events | ❌ | ✅ `emitEvent()` | Use `sol.log.log()` |
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
- ✅ Simple account validation is sufficient
- ✅ You want smallest binary size
- ✅ Performance is more important than safety

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
// Hot path: use zero_cu for 5 CU
comptime {
    zero.entry(TransferAccounts, "transfer", transfer);
}

// Complex path: use standard Anchor
pub fn initialize(ctx: anchor.Context(InitAccounts)) !void {
    // Uses full validation, PDA, init
}
```
