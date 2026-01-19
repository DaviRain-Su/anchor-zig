//! anchor-zig IDL Generator CLI
//!
//! Command-line tool for generating Anchor-compatible IDL JSON files.
//!
//! ## Standalone Usage
//!
//! This tool shows usage instructions. For actual IDL generation,
//! create a project-specific generator (see --help).
//!
//! ## Library Usage
//!
//! Import this module in your project's gen_idl.zig:
//!
//! ```zig
//! const gen = @import("anchor-zig-gen-idl");
//! const Program = @import("main.zig").Program;
//!
//! pub fn main() !void {
//!     try gen.run(Program);
//! }
//! ```

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var show_help = false;
    var show_version = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            show_help = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--version")) {
            show_version = true;
        }
    }

    const stdout = std.io.getStdOut().writer();

    if (show_version) {
        try stdout.print("anchor-zig-idl 0.1.0\n", .{});
        return;
    }

    if (show_help) {
        try printHelp(stdout);
        return;
    }

    // Default: show quick start guide
    try printQuickStart(stdout);
}

fn printHelp(w: anytype) !void {
    try w.print(
        \\anchor-zig IDL Generator
        \\========================
        \\
        \\Generate Anchor-compatible IDL JSON from Zig program definitions.
        \\
        \\USAGE:
        \\    anchor-zig-idl [OPTIONS]
        \\
        \\OPTIONS:
        \\    -h, --help       Show this help message
        \\    -v, --version    Show version information
        \\
        \\QUICK START:
        \\
        \\1. Define your program with IDL metadata in main.zig:
        \\
        \\    const anchor = @import("sol_anchor_zig");
        \\    const zero = anchor.zero_cu;
        \\    const idl = anchor.idl_zero;
        \\
        \\    pub const Program = struct {{
        \\        pub const id = PROGRAM_ID;
        \\        pub const name = "my_program";
        \\        pub const version = "0.1.0";
        \\
        \\        pub const instructions = .{{
        \\            idl.Instruction("initialize", InitAccounts, InitArgs),
        \\            idl.Instruction("process", ProcessAccounts, void),
        \\        }};
        \\
        \\        pub const accounts = .{{
        \\            idl.AccountDef("MyAccount", MyAccountData),
        \\        }};
        \\
        \\        pub const errors = enum(u32) {{
        \\            InvalidInput = 6000,
        \\        }};
        \\    }};
        \\
        \\2. Create gen_idl.zig in your project:
        \\
        \\    const std = @import("std");
        \\    const anchor = @import("sol_anchor_zig");
        \\    const idl = anchor.idl_zero;
        \\    const Program = @import("main.zig").Program;
        \\
        \\    pub fn main() !void {{
        \\        var gpa = std.heap.GeneralPurposeAllocator(.{{}}){{}}; 
        \\        defer _ = gpa.deinit();
        \\        try idl.writeJsonFile(gpa.allocator(), Program, "target/idl/program.json");
        \\        std.debug.print("Generated IDL\\n", .{{}});
        \\    }}
        \\
        \\3. Build and run:
        \\
        \\    zig build-exe src/gen_idl.zig \\
        \\        --deps solana_program_sdk,sol_anchor_zig \\
        \\        -Msolana_program_sdk=path/to/sdk/src/root.zig \\
        \\        -Msol_anchor_zig=path/to/anchor-zig/src/root.zig
        \\    
        \\    ./gen_idl
        \\
        \\TYPESCRIPT USAGE:
        \\
        \\    import {{ Program }} from "@coral-xyz/anchor";
        \\    import idl from "./target/idl/program.json";
        \\
        \\    const program = new Program(idl, programId, provider);
        \\    await program.methods.initialize().accounts({{ ... }}).rpc();
        \\
    , .{});
}

fn printQuickStart(w: anytype) !void {
    try w.print(
        \\
        \\anchor-zig IDL Generator
        \\========================
        \\
        \\This tool helps generate Anchor-compatible IDL JSON files.
        \\
        \\Run with --help for detailed usage instructions.
        \\
        \\QUICK START:
        \\
        \\1. In your program (main.zig), define Program struct with IDL metadata
        \\2. Create gen_idl.zig that imports Program and calls idl.writeJsonFile()
        \\3. Build and run gen_idl to generate target/idl/program.json
        \\4. Use the IDL with @coral-xyz/anchor TypeScript client
        \\
        \\Example gen_idl.zig:
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
// Library API for project-specific generators
// ============================================================================

/// Run IDL generation with command line argument parsing.
/// 
/// Usage in your gen_idl.zig:
/// ```zig
/// const gen = @import("anchor-zig-gen-idl");
/// const Program = @import("main.zig").Program;
/// 
/// pub fn main() !void {
///     try gen.run(Program);
/// }
/// ```
pub fn run(comptime Program: type) !void {
    const idl_zero = @import("sol_anchor_zig").idl_zero;

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
    try stdout.print("✅ Generated IDL: {s}\n", .{output_path});
}

/// Generate IDL and print to stdout.
pub fn generateToStdout(comptime Program: type) !void {
    const idl_zero = @import("sol_anchor_zig").idl_zero;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json = try idl_zero.generateJson(allocator, Program);
    defer allocator.free(json);

    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(json);
    try stdout.writeByte('\n');
}
