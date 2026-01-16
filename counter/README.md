# counter

Anchor-style Solana program template in Zig.

## Quick start

```bash
./install-solana-zig.sh solana-zig
./solana-zig/zig build --summary all
```

## IDL generation

```bash
./solana-zig/zig build idl \
  -Didl-program=src/main.zig \
  -Didl-output=idl/program.json
```

## Notes

- Uses the Solana-specific build pipeline from `solana_program_sdk`.
- CI installs the pinned `solana-zig` toolchain before building.
