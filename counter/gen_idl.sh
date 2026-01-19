#!/bin/bash
# Generate IDL for Counter Program
#
# This script uses system zig (not solana-zig) to build and run the IDL generator.
# 
# Usage:
#   ./gen_idl.sh
#   ./gen_idl.sh -o custom/path/idl.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_PATH="${1:-target/idl/counter.json}"

# Create output directory
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Build IDL generator with system zig
echo "Building IDL generator..."

# Check if system zig is available
if ! command -v zig &> /dev/null; then
    echo "Error: zig not found in PATH"
    echo "Please install Zig 0.14+ or add it to your PATH"
    exit 1
fi

# Create a temporary build directory
BUILD_DIR=".idl-build"
mkdir -p "$BUILD_DIR"

# Compile gen_idl.zig
zig build-exe \
    src/gen_idl.zig \
    -femit-bin="$BUILD_DIR/gen_idl" \
    -O ReleaseFast \
    --deps solana_program_sdk,sol_anchor_zig \
    -Msolana_program_sdk=../solana-program-sdk-zig/src/root.zig \
    -Msol_anchor_zig=../src/root.zig \
    2>/dev/null || {
        echo "Note: Using zig might require specific version. Trying alternative..."
        # Alternative: just describe what to do
        echo ""
        echo "To generate IDL manually, create a gen_idl executable that imports"
        echo "your Program definition and calls idl_zero.writeJsonFile()"
        echo ""
        echo "Or use the following pattern in your build system:"
        echo ""
        echo "  const idl = @import(\"sol_anchor_zig\").idl_zero;"
        echo "  const Program = @import(\"main.zig\").Program;"
        echo "  try idl.writeJsonFile(allocator, Program, \"$OUTPUT_PATH\");"
        exit 1
    }

# Run IDL generator
echo "Generating IDL..."
"$BUILD_DIR/gen_idl" -o "$OUTPUT_PATH"

# Cleanup
rm -rf "$BUILD_DIR"

echo "✅ Generated: $OUTPUT_PATH"
