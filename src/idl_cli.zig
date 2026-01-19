//! IDL CLI Tool
//!
//! Command-line interface for generating Anchor-compatible IDL files.
//!
//! ## Usage
//!
//! Build the CLI tool, then run:
//!
//! ```bash
//! # Generate IDL from program module
//! anchor-zig-idl --output target/idl/counter.json
//! ```
//!
//! ## Integration with Anchor TypeScript Client
//!
//! ```typescript
//! import { Program } from "@coral-xyz/anchor";
//! import idl from "./target/idl/counter.json";
//!
//! const program = new Program(idl, programId, provider);
//! await program.methods.increment().accounts({ ... }).rpc();
//! ```

const std = @import("std");
const idl_zero = @import("idl_zero.zig");

/// CLI entry point for IDL generation
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_path: []const u8 = "target/idl/program.json";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return;
        }
    }

    // Note: In actual usage, the program module is imported at comptime
    // This CLI tool is a template - users should modify it for their program

    const stderr = std.io.getStdErr().writer();
    try stderr.print(
        \\anchor-zig IDL Generator
        \\
        \\This is a template CLI tool. To generate IDL for your program:
        \\
        \\1. Create a build step in your build.zig that calls idl_zero.generateJson()
        \\2. Or create a custom CLI that imports your program module
        \\
        \\Example build.zig integration:
        \\
        \\    const idl_step = b.step("idl", "Generate IDL");
        \\    const idl_exe = b.addExecutable(.{{
        \\        .name = "gen-idl",
        \\        .root_source_file = .{{ .cwd_relative = "src/gen_idl.zig" }},
        \\    }});
        \\    idl_step.dependOn(&b.addRunArtifact(idl_exe).step);
        \\
        \\Output path: {s}
        \\
    , .{output_path});
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\anchor-zig IDL Generator
        \\
        \\Usage: anchor-zig-idl [options]
        \\
        \\Options:
        \\  -o, --output <path>  Output IDL file path (default: target/idl/program.json)
        \\  -h, --help           Show this help message
        \\
        \\Integration:
        \\
        \\In your program's gen_idl.zig:
        \\
        \\    const std = @import("std");
        \\    const idl = @import("sol_anchor_zig").idl_zero;
        \\    const Program = @import("main.zig").Program;
        \\
        \\    pub fn main() !void {{
        \\        var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}}; 
        \\        defer _ = gpa.deinit();
        \\        try idl.writeJsonFile(gpa.allocator(), Program, "target/idl/program.json");
        \\    }}
        \\
    , .{});
}

// ============================================================================
// Comptime IDL Generation Helper
// ============================================================================

/// Generate IDL at comptime and embed in binary
/// Useful for programs that want to serve their own IDL
pub fn comptimeIdl(comptime program: anytype) []const u8 {
    comptime {
        var buffer: [64 * 1024]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&buffer);

        const json = idl_zero.generateJson(fba.allocator(), program) catch |err| {
            @compileError("Failed to generate IDL: " ++ @errorName(err));
        };

        // Copy to comptime storage
        var result: [json.len]u8 = undefined;
        @memcpy(&result, json);
        return &result;
    }
}
