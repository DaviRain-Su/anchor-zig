//! anchor-zig IDL Generator CLI
//!
//! Generates Anchor-compatible IDL JSON from Zig program definitions.
//!
//! ## Usage
//!
//! ```bash
//! # Build the generator
//! zig build
//!
//! # Generate IDL (program module must be imported at compile time)
//! ./zig-out/bin/gen-idl -o target/idl/program.json
//! ```
//!
//! ## Integration
//!
//! Create a project-specific generator that imports your program:
//!
//! ```zig
//! // src/gen_idl.zig
//! const gen = @import("anchor-zig-gen-idl");
//! const Program = @import("main.zig").Program;
//!
//! pub fn main() !void {
//!     try gen.run(Program);
//! }
//! ```

const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_path: ?[]const u8 = null;
    var show_help = false;
    var show_version = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            } else {
                try printError("Missing argument for --output");
                return;
            }
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            show_version = true;
        }
    }

    if (show_version) {
        try printVersion();
        return;
    }

    if (show_help) {
        try printHelp();
        return;
    }

    // Show usage instructions
    try printUsageInstructions(output_path);
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("anchor-zig-idl 0.1.0\n", .{});
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print(
        \\anchor-zig IDL Generator
        \\
        \\Generates Anchor-compatible IDL JSON from Zig program definitions.
        \\
        \\USAGE:
        \\    gen-idl [OPTIONS]
        \\
        \\OPTIONS:
        \\    -o, --output <PATH>    Output file path (default: target/idl/program.json)
        \\    -h, --help             Show this help message
        \\    -v, --version          Show version information
        \\
        \\INTEGRATION:
        \\
        \\    This is a template tool. To generate IDL for your program, create a
        \\    project-specific generator:
        \\
        \\    1. Create gen_idl.zig in your project:
        \\
        \\       const std = @import("std");
        \\       const anchor = @import("sol_anchor_zig");
        \\       const idl = anchor.idl_zero;
        \\       const Program = @import("main.zig").Program;
        \\
        \\       pub fn main() !void {{
        \\           var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}}; 
        \\           defer _ = gpa.deinit();
        \\           try idl.writeJsonFile(gpa.allocator(), Program, "target/idl/program.json");
        \\           std.debug.print("Generated IDL\\n", .{{}});
        \\       }}
        \\
        \\    2. Add to build.zig:
        \\
        \\       const idl_exe = b.addExecutable(.{{
        \\           .name = "gen-idl",
        \\           .root_source_file = b.path("src/gen_idl.zig"),
        \\           .target = b.host,
        \\       }});
        \\       // Add imports...
        \\       
        \\       const idl_step = b.step("idl", "Generate IDL");
        \\       idl_step.dependOn(&b.addRunArtifact(idl_exe).step);
        \\
        \\    3. Run: zig build idl
        \\
        \\EXAMPLES:
        \\
        \\    # Generate IDL to default path
        \\    zig build idl
        \\
        \\    # Generate IDL to custom path
        \\    ./zig-out/bin/gen-idl -o ./my-idl.json
        \\
    , .{});
}

fn printUsageInstructions(output_path: ?[]const u8) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print(
        \\
        \\anchor-zig IDL Generator
        \\========================
        \\
        \\This tool helps generate Anchor-compatible IDL JSON files.
        \\
        \\Output path: {s}
        \\
        \\To generate IDL for your program, you need to create a project-specific
        \\generator that imports your program module. See --help for details.
        \\
        \\Quick Start:
        \\
        \\  1. Define your program with IDL metadata:
        \\
        \\     const idl = @import("sol_anchor_zig").idl_zero;
        \\
        \\     pub const Program = struct {{
        \\         pub const id = PROGRAM_ID;
        \\         pub const name = "my_program";
        \\         pub const version = "0.1.0";
        \\
        \\         pub const instructions = .{{
        \\             idl.Instruction("initialize", InitAccounts, InitArgs),
        \\             idl.Instruction("process", ProcessAccounts, void),
        \\         }};
        \\
        \\         pub const accounts = .{{
        \\             idl.AccountDef("MyAccount", MyAccountData),
        \\         }};
        \\
        \\         pub const errors = enum(u32) {{
        \\             InvalidInput = 6000,
        \\         }};
        \\     }};
        \\
        \\  2. Create gen_idl.zig and add build step (see --help)
        \\
        \\  3. Run: zig build idl
        \\
    , .{output_path orelse "target/idl/program.json"});
}

fn printError(msg: []const u8) !void {
    const stderr = std.io.getStdErr().writer();
    try stderr.print("Error: {s}\n", .{msg});
}

// ============================================================================
// Library Functions (for use in project-specific generators)
// ============================================================================

/// Run IDL generation with command line argument parsing
pub fn run(comptime Program: type) !void {
    const idl_zero = @import("idl_zero.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_path: []const u8 = "target/idl/program.json";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            }
        }
    }

    try idl_zero.writeJsonFile(allocator, Program, output_path);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Generated IDL: {s}\n", .{output_path});
}

/// Generate IDL to stdout
pub fn generateToStdout(comptime Program: type) !void {
    const idl_zero = @import("idl_zero.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = try idl_zero.generateJson(allocator, Program);
    defer allocator.free(json);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(json);
    try stdout.writeByte('\n');
}
