# anchor-zig CLI

Command-line tool for anchor-zig development workflow.

## Installation

### Build from source

```bash
cd tools/anchor-zig-cli
zig build -Doptimize=ReleaseFast

# The binary will be at:
# zig-out/bin/anchor-zig
```

### Add to PATH

```bash
# Add to your shell profile (.bashrc, .zshrc, etc.)
export PATH="$PATH:/path/to/anchor-zig/tools/anchor-zig-cli/zig-out/bin"
```

### Configure solana-zig

For building Solana programs (SBF target), you need to use `solana-zig` compiler:

```bash
# Set environment variable
export SOLANA_ZIG=/path/to/solana-zig/zig

# Or use --zig option
anchor-zig --zig /path/to/solana-zig/zig build
```

## Commands

### `init` - Create a new project

Initialize a new anchor-zig project with the recommended structure.

```bash
anchor-zig init my_program
```

This creates:
```
my_program/
├── src/
│   ├── main.zig      # Main program code (with test example)
│   └── gen_idl.zig   # IDL generator
├── idl/              # Generated IDL files
├── client/           # Client SDK
├── tests/            # Integration tests
├── target/           # Deployment artifacts
├── build.zig         # Build configuration (with test step)
├── build.zig.zon     # Dependencies
├── Anchor.toml       # Anchor configuration
├── .gitignore
└── README.md
```

### `build` - Build the program

Build the Solana program.

```bash
anchor-zig build
anchor-zig build --release
```

### `test` - Run tests

Run program unit tests.

```bash
anchor-zig test
```

If no test step is found in build.zig, helpful instructions are provided:

```
⚠️  No test step found in build.zig

To add tests to your project:
1. Add test declarations in your source files:
   test "example" { ... }

2. Add test step to build.zig:
   const unit_tests = b.addTest(.{ ... });
   const test_step = b.step("test", "Run tests");
   test_step.dependOn(&run_tests.step);
```

### `verify` - Verify deployed program

Compare local build with on-chain deployed program.

```bash
# Verify against localnet (default)
anchor-zig verify <PROGRAM_ID>

# Verify against devnet
anchor-zig verify <PROGRAM_ID> --network devnet

# Specify local program path
anchor-zig verify <PROGRAM_ID> -p zig-out/lib/my_program.so
```

Example output:
```
Verifying program: 9YVfTx1E16vs7pzSSfC8wuqz19a4uGC1jtJP3tbKEHYC
  Network: localnet
  Local program: zig-out/lib/counter.so

Reading local program...
  Local program size: 41592 bytes

Fetching on-chain program...
  On-chain program size: 41592 bytes

Comparing programs...
✅ Programs match! Verification successful.
```

### `idl` - IDL utilities

Generate and manage IDL files.

```bash
# Generate IDL from program
anchor-zig idl generate
anchor-zig idl generate -o custom/path/idl.json

# Create gen_idl.zig template
anchor-zig idl init

# Fetch IDL from on-chain program
anchor-zig idl fetch <PROGRAM_ID>
anchor-zig idl fetch <PROGRAM_ID> -o idl/fetched.json --network devnet
```

### `deploy` - Deploy program

Deploy the program to a Solana network.

```bash
# Deploy to localnet (default)
anchor-zig deploy

# Deploy to devnet
anchor-zig deploy --network devnet

# Deploy to mainnet
anchor-zig deploy --network mainnet --keypair ~/.config/solana/deploy.json

# Custom program path
anchor-zig deploy --program path/to/program.so
```

Networks:
- `localnet` - Local validator (http://localhost:8899)
- `devnet` - Solana Devnet
- `testnet` - Solana Testnet
- `mainnet` - Solana Mainnet Beta

### `keys` - Keypair management

Manage Solana keypairs.

```bash
# Generate a new keypair
anchor-zig keys generate
anchor-zig keys generate -o program-keypair.json

# Show public key from keypair file
anchor-zig keys show keypair.json
```

### `clean` - Clean build artifacts

Remove build artifacts.

```bash
anchor-zig clean
```

This removes:
- `zig-out/`
- `.zig-cache/`

## Quick Start

```bash
# Create a new project
anchor-zig init my_counter

# Navigate to project
cd my_counter

# Edit build.zig.zon to set dependency paths
# Edit src/main.zig to implement your program

# Build the program (requires solana-zig)
SOLANA_ZIG=/path/to/solana-zig/zig anchor-zig build
# Or: anchor-zig --zig /path/to/solana-zig/zig build

# Run tests
anchor-zig test

# Generate IDL
anchor-zig idl generate

# Deploy (start local validator first)
solana-test-validator &
anchor-zig deploy -p zig-out/lib/my_counter.so

# Verify deployment
anchor-zig verify <PROGRAM_ID> -p zig-out/lib/my_counter.so
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `SOLANA_ZIG` | Path to solana-zig compiler (for SBF target support) |

## Requirements

- Zig 0.15.x (standard zig for IDL generation, solana-zig for program building)
- Solana CLI tools (for deploy, keys, verify commands)
- anchor-zig library
- solana-program-sdk-zig

## Version

```bash
anchor-zig --version
```

## Help

```bash
anchor-zig --help
anchor-zig <command> --help
```

## Feature Status

| Command | Status | Description |
|---------|--------|-------------|
| `init` | ✅ | Create new project with templates |
| `build` | ✅ | Build Solana program |
| `test` | ✅ | Run tests with helpful guidance |
| `deploy` | ✅ | Deploy to any network |
| `verify` | ✅ | Compare local/on-chain bytecode |
| `idl generate` | ✅ | Generate IDL from source |
| `idl init` | ✅ | Create IDL generator template |
| `idl fetch` | ✅ | Fetch IDL from on-chain |
| `keys generate` | ✅ | Generate new keypair |
| `keys show` | ✅ | Show public key |
| `clean` | ✅ | Remove build artifacts |

## License

MIT
