# sol-anchor-zig

Anchor-like framework for Solana program development in Zig.

## Quick Start

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const CounterData = struct {
    count: u64,
};

const Counter = anchor.Account(CounterData, .{
    .discriminator = anchor.accountDiscriminator("Counter"),
});

const InitializeAccounts = struct {
    payer: anchor.SignerMut,
    counter: Counter,
};

const InitializeArgs = struct {
    initial: u64,
};

const Program = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
    };

    pub fn initialize(ctx: anchor.Context(InitializeAccounts), args: InitializeArgs) !void {
        ctx.accounts.counter.data.count = args.initial;
    }
};

pub fn processInstruction(
    program_id: *const sol.PublicKey,
    accounts: []const sol.account.Account.Info,
    data: []const u8,
) !void {
    try anchor.ProgramEntry(Program).dispatchWithConfig(program_id, accounts, data, .{});
}
```

## Typed DSL (No String Field Names)

```zig
const anchor = @import("sol_anchor_zig");
const dsl = anchor.dsl;

const CounterData = struct { count: u64 };
const InitializeArgs = struct { initial: u64 };

const InitializeAccounts = dsl.Accounts(.{
    .payer = dsl.SignerMut,
    .counter = dsl.Init(CounterData, .{ .payer = .payer, .name = "Counter" }),
});

const Initialize = dsl.Instr("initialize", InitializeAccounts, InitializeArgs);

pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
    ctx.accounts.counter.data.count = args.initial;
}
```

More details: `docs/README.md`

## Interface + CPI Helpers

```zig
const ProgramIds = [_]sol.PublicKey{
    sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    sol.PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"),
};

const InterfaceProgram = anchor.InterfaceProgram(ProgramIds[0..]);
const RawAccount = anchor.InterfaceAccountInfo(.{ .mut = true });

const Accounts = struct {
    authority: anchor.Signer,
    target_program: InterfaceProgram,
    remaining_account: RawAccount,
};

const Program = struct {
    pub const instructions = struct {
        pub const deposit = anchor.Instruction(.{
            .Accounts = Accounts,
            .Args = struct { amount: u64 },
        });
    };
};

var iface = try anchor.Interface(Program, .{ .program_ids = ProgramIds[0..] }).init(allocator, program_id);
const ix = try iface.instruction("deposit", accounts, .{ .amount = 1 });
defer ix.deinit();

const remaining = [_]*const sol.account.Account.Info{ &extra_info };
const ix_with_remaining = try iface.instructionWithRemaining("deposit", accounts, .{ .amount = 1 }, remaining[0..]);
defer ix_with_remaining.deinit();
```

Notes:
- Instruction builders return an `OwnedInstruction`; call `deinit()` when done.
- Interface CPI accounts accept `AccountMeta`, `AccountInfo`, or types with `toAccountInfo()`.
- Remaining accounts can be `[]AccountMeta` or `[]*const AccountInfo`.
- `anchor.Interface` provides `invoke` and `invokeSigned` helpers.
- Use `InterfaceConfig.meta_merge` if you need duplicate `AccountMeta` merging.

## Zero-CU API (5-7 CU) ⭐ Recommended

High-level abstractions with zero runtime overhead:

```zig
const anchor = @import("sol_anchor_zig");
const zero = anchor.zero_cu;

const CounterData = struct {
    count: u64,
};

// Define accounts with type markers
const MyAccounts = struct {
    authority: zero.Signer(0),           // Signer, 0 bytes data
    counter: zero.Mut(CounterData),      // Writable, typed data
};

pub fn increment(ctx: zero.Ctx(MyAccounts)) !void {
    if (!ctx.accounts.authority.isSigner()) {
        return error.MissingSigner;
    }
    ctx.accounts.counter.getMut().count += 1;  // Direct typed access
}

// Single instruction (5 CU)
comptime {
    zero.entry(MyAccounts, "increment", increment);
}

// Multi-instruction (7 CU each)
comptime {
    zero.multi(MyAccounts, .{
        zero.inst("initialize", initialize),
        zero.inst("increment", increment),
    });
}
```

### Account Type Markers

| Type | Description |
|------|-------------|
| `zero.Signer(data_size)` | Transaction signer |
| `zero.Mut(T)` or `zero.Mut(size)` | Writable account |
| `zero.Readonly(T)` or `zero.Readonly(size)` | Read-only account |

### Typed Data Access

```zig
// Read typed data
const count = ctx.accounts.counter.get().count;

// Write typed data
ctx.accounts.counter.getMut().count += 1;

// Access account info
const pubkey = ctx.accounts.authority.id();
const owner = ctx.accounts.counter.ownerId();
const lamports = ctx.accounts.counter.lamports();
```

### CU Comparison

| Implementation | CU | Size | Notes |
|----------------|-----|------|-------|
| Raw Zig | 5 | 1.2 KB | No framework |
| **zero_cu single** | **5** | 1.3 KB | **Zero overhead!** |
| **zero_cu multi** | **7** | 1.4 KB | **+2 CU dispatch** |
| Standard Anchor | ~150 | 7+ KB | Full validation |

### Reference (solana-program-rosetta)

| Language | CU |
|----------|-----|
| Rust | 14 |
| Zig | 15 |
| **anchor-zig** | **5** |

**anchor-zig is 3x faster than rosetta!**

## Build + Test

```bash
./install-solana-zig.sh solana-zig
./solana-zig/zig build -Drelease
./solana-zig/zig build test --summary all
```

## Template

```bash
./scripts/new-anchor-project.sh /path/to/project project_name
./scripts/sync-template.sh /path/to/project
```

## IDL + Zig Client

```zig
const anchor = @import("sol_anchor_zig");
const sol = anchor.sdk;

const MyProgram = struct {
    pub const id = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const instructions = struct {
        pub const initialize = anchor.Instruction(.{
            .Accounts = InitializeAccounts,
            .Args = InitializeArgs,
        });
    };
};

const idl_json = try anchor.generateIdlJson(allocator, MyProgram, .{});
const client_src = try anchor.generateZigClient(allocator, MyProgram, .{});
```

## IDL Output (Build Step)

```bash
./solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/my_program.json
```

`idl-program` must export `pub const Program`.

## Dependencies (build.zig.zon)

```zig
.dependencies = .{
    .solana_program_sdk = .{
        .url = "https://github.com/DaviRain-Su/solana-program-sdk-zig/archive/refs/heads/dev.tar.gz",
        .hash = "solana_program_sdk-0.17.1-wGj9UNYVHAD_uLlbUOhOAMLL08lQOXMm3Ss3Xw4VYvkt",
    },
    .sol_anchor_zig = .{
        .url = "https://github.com/DaviRain-Su/anchor-zig/archive/refs/heads/main.tar.gz",
        .hash = "sol_anchor_zig-0.1.0-xwtyYdpyCwCeBCQdaz4WPoX5ae63POhjg0BQC0wfehZ-",
    },
},
```

Fetch the latest hash with:

```bash
./solana-zig/zig fetch https://github.com/DaviRain-Su/anchor-zig/archive/refs/heads/main.tar.gz
```

## Example Project

The `counter/` project contains a minimal program and a TypeScript client:
- `counter/src/main.zig`
- `counter/client/src/index.ts`
