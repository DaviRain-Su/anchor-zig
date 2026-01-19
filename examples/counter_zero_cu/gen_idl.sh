#!/bin/bash
# Generate IDL for counter program
# Requires standard zig (not solana-zig)

set -e

cd "$(dirname "$0")"

# Use system zig for native builds
zig build-exe \
    -fsummary \
    src/gen_idl.zig \
    --deps solana_program_sdk,sol_anchor_zig \
    -Msolana_program_sdk=../../solana-program-sdk-zig/src/root.zig \
    -Msol_anchor_zig=../../src/root.zig \
    -o zig-out/gen_idl

mkdir -p target/idl
./zig-out/gen_idl -o target/idl/counter.json

echo "Generated: target/idl/counter.json"
