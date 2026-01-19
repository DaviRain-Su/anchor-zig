# Solana Program Template

This is the recommended template for Solana programs using anchor-zig.

## Features

- ✅ Multiple instructions with different account layouts
- ✅ Automatic constraint validation (owner, signer, has_one, seeds)
- ✅ IDL generation for TypeScript client
- ✅ ~18 CU overhead per instruction
- ✅ Small binary size (~2-5 KB typical)

## Quick Start

### 1. Copy this template

```bash
cp -r template/program my_program
cd my_program
```

### 2. Update configuration

Edit `build.zig.zon`:
- Change `.name` to your program name
- Update dependency paths

Edit `src/main.zig`:
- Replace `PROGRAM_ID` with your program address
- Define your account data structures
- Define instruction accounts with constraints
- Implement instruction handlers

### 3. Build

```bash
# Using solana-zig compiler
../path/to/solana-zig/zig build

# Output: zig-out/lib/my_program.so
```

### 4. Deploy

```bash
solana program deploy zig-out/lib/my_program.so
```

### 5. Generate IDL (optional)

```bash
./gen_idl.sh  # or manually build gen_idl.zig
# Output: target/idl/my_program.json
```

## Program Structure

```
my_program/
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies
├── src/
│   ├── main.zig        # Program code
│   └── gen_idl.zig     # IDL generator
└── README.md
```

## Recommended Pattern

```zig
// 1. Define account data
pub const MyData = struct {
    value: u64,
    authority: sol.PublicKey,
};

// 2. Define instruction accounts with constraints
pub const MyAccounts = struct {
    authority: zero.Signer(0),
    account: zero.Account(MyData, .{
        .owner = PROGRAM_ID,
        .has_one = &.{"authority"},
    }),
};

// 3. Implement handler
pub fn my_instruction(ctx: zero.Ctx(MyAccounts)) !void {
    ctx.accounts.account.getMut().value += 1;
}

// 4. Export with validation (RECOMMENDED)
comptime {
    zero.program(.{
        zero.ixValidated("my_instruction", MyAccounts, my_instruction),
    });
}
```

## Constraint Reference

| Constraint | Syntax | Description |
|------------|--------|-------------|
| owner | `.owner = PUBKEY` | Verify account owner |
| signer | `zero.Signer(size)` | Must be transaction signer |
| has_one | `.has_one = &.{"field"}` | Field must match account key |
| seeds | `.seeds = &.{...}` | PDA verification |
| address | `.address = PUBKEY` | Exact address match |

## Performance

| Metric | Value |
|--------|-------|
| CU overhead | ~18 per instruction |
| Binary size | ~2-5 KB typical |
| Compile time | Fast (comptime evaluation) |

## TypeScript Client

```typescript
import { Program } from "@coral-xyz/anchor";
import idl from "./target/idl/my_program.json";

const program = new Program(idl, programId, provider);

// Call instruction
await program.methods
    .myInstruction({ value: 100 })
    .accounts({
        authority: wallet.publicKey,
        account: accountPda,
    })
    .rpc();
```
