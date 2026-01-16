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

## Client test (local validator)

```bash
./solana-zig/zig build -Drelease
solana program deploy --url http://127.0.0.1:8899 \
  --program-id target/deploy/counter-keypair.json \
  zig-out/lib/anchor_program.so
cd client
npm install
npm test
```

The client uses Anchor's `EventParser` to decode `CounterEvent` logs.

## Notes

- Uses the Solana-specific build pipeline from `solana_program_sdk`.
- CI installs the pinned `solana-zig` toolchain before building.
