//! anchor-zig CLI
//!
//! Command-line tool for anchor-zig development workflow.
//!
//! ## Commands
//!
//! - `init` - Initialize a new anchor-zig project
//! - `idl` - IDL generation utilities
//! - `build` - Build the Solana program
//! - `test` - Run tests
//! - `deploy` - Deploy program to network
//! - `verify` - Verify deployed program
//!
//! ## Usage
//!
//! ```bash
//! # Initialize new project
//! anchor-zig init my_project
//!
//! # Generate IDL (in project directory)
//! anchor-zig idl generate
//!
//! # Build program
//! anchor-zig build
//!
//! # Test program
//! anchor-zig test
//!
//! # Deploy program
//! anchor-zig deploy
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;

const VERSION = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "help")) {
        try printUsage();
    } else if (std.mem.eql(u8, command, "-v") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "version")) {
        try printVersion();
    } else if (std.mem.eql(u8, command, "init")) {
        try cmdInit(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "idl")) {
        try cmdIdl(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "build")) {
        try cmdBuild(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "test")) {
        try cmdTest(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "deploy")) {
        try cmdDeploy(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "verify")) {
        try cmdVerify(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "keys")) {
        try cmdKeys(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "clean")) {
        try cmdClean(allocator, args[2..]);
    } else {
        try printError("Unknown command: {s}", .{command});
        try printUsage();
    }
}

// ============================================================================
// Output Helpers (Zig 0.15+ I/O API)
// ============================================================================

/// Thread-local stdout buffer
threadlocal var stdout_buffer: [4096]u8 = undefined;
threadlocal var stderr_buffer: [4096]u8 = undefined;

fn getStdout() *std.Io.Writer {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    return &impl.interface;
}

fn getStderr() *std.Io.Writer {
    var impl = std.fs.File.stderr().writer(&stderr_buffer);
    return &impl.interface;
}

fn printVersion() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print("anchor-zig {s}\n", .{VERSION});
    try out.flush();
}

fn printError(comptime fmt: []const u8, args: anytype) !void {
    var impl = std.fs.File.stderr().writer(&stderr_buffer);
    const err_out: *std.Io.Writer = &impl.interface;
    try err_out.print("error: " ++ fmt ++ "\n", args);
    try err_out.flush();
}

fn printInfo(comptime fmt: []const u8, args: anytype) !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(fmt ++ "\n", args);
    try out.flush();
}

fn printUsage() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig - Solana development framework for Zig
        \\
        \\USAGE:
        \\    anchor-zig <COMMAND> [OPTIONS]
        \\
        \\COMMANDS:
        \\    init <name>       Create a new anchor-zig project
        \\    build             Build the Solana program
        \\    test              Run program tests
        \\    deploy            Deploy program to network
        \\    verify            Verify deployed program
        \\    idl <subcommand>  IDL generation utilities
        \\    keys <subcommand> Keypair management
        \\    clean             Clean build artifacts
        \\    help              Show this help message
        \\    version           Show version information
        \\
        \\OPTIONS:
        \\    -h, --help        Show help for a command
        \\    -v, --version     Show version information
        \\
        \\EXAMPLES:
        \\    anchor-zig init my_program
        \\    anchor-zig build
        \\    anchor-zig test
        \\    anchor-zig deploy --network devnet
        \\    anchor-zig idl generate -o idl/program.json
        \\
        \\Use 'anchor-zig <command> --help' for more information about a command.
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// init Command
// ============================================================================

fn cmdInit(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (args.len == 0) {
        try printError("Missing project name", .{});
        try printInitHelp();
        return;
    }

    const name = args[0];

    // Check for help flag
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printInitHelp();
            return;
        }
    }

    try printInfo("Creating new anchor-zig project: {s}", .{name});
    try printInfo("", .{});

    // Create directory structure
    try createProjectStructure(name);

    try printInfo("✅ Project created successfully!", .{});
    try printInfo("", .{});
    try printInfo("Next steps:", .{});
    try printInfo("  cd {s}", .{name});
    try printInfo("  # Edit build.zig.zon to set correct dependency paths", .{});
    try printInfo("  # Edit src/main.zig to implement your program", .{});
    try printInfo("  anchor-zig build", .{});
    try printInfo("  anchor-zig idl generate", .{});
}

fn printInitHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig init - Create a new anchor-zig project
        \\
        \\USAGE:
        \\    anchor-zig init <name> [OPTIONS]
        \\
        \\ARGUMENTS:
        \\    <name>    Name of the project to create
        \\
        \\OPTIONS:
        \\    -h, --help    Show this help message
        \\
        \\EXAMPLES:
        \\    anchor-zig init my_program
        \\    anchor-zig init counter
        \\
    , .{});
    try out.flush();
}

fn createProjectStructure(name: []const u8) !void {
    const cwd = std.fs.cwd();

    // Create directories
    cwd.makeDir(name) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try printError("Directory already exists: {s}", .{name});
            return error.PathAlreadyExists;
        },
        else => return err,
    };

    var project_dir = try cwd.openDir(name, .{});
    defer project_dir.close();

    try project_dir.makeDir("src");
    try project_dir.makeDir("idl");
    try project_dir.makeDir("client");
    try project_dir.makeDir("tests");
    try project_dir.makeDir("target");

    // Create main.zig
    const main_content = getMainTemplate();
    var main_file = try project_dir.createFile("src/main.zig", .{});
    defer main_file.close();
    try main_file.writeAll(main_content);

    // Create gen_idl.zig
    const gen_idl_content = getGenIdlTemplate();
    var gen_idl_file = try project_dir.createFile("src/gen_idl.zig", .{});
    defer gen_idl_file.close();
    try gen_idl_file.writeAll(gen_idl_content);

    // Create build.zig
    const build_content = getBuildTemplate();
    var build_file = try project_dir.createFile("build.zig", .{});
    defer build_file.close();
    try build_file.writeAll(build_content);

    // Create build.zig.zon
    const zon_content = getBuildZonTemplate();
    var zon_file = try project_dir.createFile("build.zig.zon", .{});
    defer zon_file.close();
    try zon_file.writeAll(zon_content);

    // Create README.md
    const readme_content = getReadmeTemplate();
    var readme_file = try project_dir.createFile("README.md", .{});
    defer readme_file.close();
    try readme_file.writeAll(readme_content);

    // Create .gitignore
    const gitignore_content = getGitignoreTemplate();
    var gitignore_file = try project_dir.createFile(".gitignore", .{});
    defer gitignore_file.close();
    try gitignore_file.writeAll(gitignore_content);

    // Create Anchor.toml
    const anchor_toml_content = getAnchorTomlTemplate();
    var anchor_toml_file = try project_dir.createFile("Anchor.toml", .{});
    defer anchor_toml_file.close();
    try anchor_toml_file.writeAll(anchor_toml_content);

    try printInfo("  Created {s}/", .{name});
    try printInfo("  Created {s}/src/main.zig", .{name});
    try printInfo("  Created {s}/src/gen_idl.zig", .{name});
    try printInfo("  Created {s}/build.zig", .{name});
    try printInfo("  Created {s}/build.zig.zon", .{name});
    try printInfo("  Created {s}/README.md", .{name});
    try printInfo("  Created {s}/.gitignore", .{name});
    try printInfo("  Created {s}/Anchor.toml", .{name});
    try printInfo("  Created {s}/idl/", .{name});
    try printInfo("  Created {s}/client/", .{name});
    try printInfo("  Created {s}/tests/", .{name});
    try printInfo("  Created {s}/target/", .{name});
}

fn getMainTemplate() []const u8 {
    return
        \\//! Solana Program using anchor-zig
        \\//!
        \\//! Build: zig build
        \\//! Generate IDL: zig build idl
        \\
        \\const std = @import("std");
        \\const anchor = @import("sol_anchor_zig");
        \\const sol = anchor.sdk;
        \\
        \\// ============================================================================
        \\// Program Configuration
        \\// ============================================================================
        \\
        \\/// Program ID - Replace with your deployed program address
        \\pub const PROGRAM_ID = sol.PublicKey.comptimeFromBase58("11111111111111111111111111111111");
        \\
        \\// ============================================================================
        \\// Account Data Structures
        \\// ============================================================================
        \\
        \\/// Counter account data
        \\pub const Counter = extern struct {
        \\    /// Account discriminator (8 bytes)
        \\    discriminator: [8]u8,
        \\    /// Authority that can modify the counter
        \\    authority: sol.PublicKey,
        \\    /// Current counter value
        \\    count: u64,
        \\
        \\    pub const SIZE = 8 + 32 + 8;
        \\    pub const DISCRIMINATOR = anchor.discriminator.accountDiscriminator("Counter");
        \\};
        \\
        \\// ============================================================================
        \\// Instruction Handlers
        \\// ============================================================================
        \\
        \\/// Initialize a new counter account
        \\pub fn initialize(
        \\    accounts: struct {
        \\        counter: *Counter,
        \\        authority: sol.PublicKey,
        \\    },
        \\) !void {
        \\    accounts.counter.discriminator = Counter.DISCRIMINATOR;
        \\    accounts.counter.authority = accounts.authority;
        \\    accounts.counter.count = 0;
        \\}
        \\
        \\/// Increment the counter
        \\pub fn increment(
        \\    accounts: struct {
        \\        counter: *Counter,
        \\        authority: sol.PublicKey,
        \\    },
        \\) !void {
        \\    // Verify authority
        \\    if (!std.mem.eql(u8, &accounts.counter.authority.data, &accounts.authority.data)) {
        \\        return error.Unauthorized;
        \\    }
        \\    accounts.counter.count +|= 1;
        \\}
        \\
        \\// ============================================================================
        \\// Program Definition
        \\// ============================================================================
        \\
        \\pub const Program = struct {
        \\    pub const id = PROGRAM_ID;
        \\    pub const name = "counter";
        \\    pub const version = "0.1.0";
        \\
        \\    pub const instructions = .{
        \\        .{ "initialize", initialize, "Initialize a new counter" },
        \\        .{ "increment", increment, "Increment the counter" },
        \\    };
        \\
        \\    pub const accounts = .{
        \\        .{ "Counter", Counter, "Counter account state" },
        \\    };
        \\};
        \\
    ;
}

fn getGenIdlTemplate() []const u8 {
    return
        \\//! IDL Generator
        \\//!
        \\//! Generates Anchor-compatible IDL JSON file.
        \\//!
        \\//! Usage: zig build idl
        \\
        \\const std = @import("std");
        \\const anchor = @import("sol_anchor_zig");
        \\const idl = anchor.idl;
        \\const program_main = @import("main.zig");
        \\const Program = program_main.Program;
        \\
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\
        \\    const args = try std.process.argsAlloc(allocator);
        \\    defer std.process.argsFree(allocator, args);
        \\
        \\    var output_path: []const u8 = "idl/program.json";
        \\    var i: usize = 1;
        \\    while (i < args.len) : (i += 1) {
        \\        if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
        \\            i += 1;
        \\            if (i < args.len) {
        \\                output_path = args[i];
        \\            }
        \\        }
        \\    }
        \\
        \\    // Generate IDL using the anchor-zig library
        \\    try idl.writeJsonFile(allocator, Program, output_path);
        \\
        \\    var stdout_buf: [256]u8 = undefined;
        \\    var impl = std.fs.File.stdout().writer(&stdout_buf);
        \\    const stdout: *std.Io.Writer = &impl.interface;
        \\    try stdout.print("✅ Generated IDL: {s}\n", .{output_path});
        \\    try stdout.flush();
        \\}
        \\
    ;
}

fn getBuildTemplate() []const u8 {
    return
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const optimize = b.standardOptimizeOption(.{});
        \\
        \\    const solana_dep = b.dependency("solana_program_sdk", .{});
        \\    const anchor_dep = b.dependency("sol_anchor_zig", .{});
        \\
        \\    // Main program (SBF target for Solana)
        \\    const program = b.addExecutable(.{
        \\        .name = "program",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = solana_dep.namedLazyPath("sbf-target"),
        \\            .optimize = .ReleaseFast,
        \\        }),
        \\    });
        \\    program.root_module.addImport("solana_program_sdk", solana_dep.module("solana_program_sdk"));
        \\    program.root_module.addImport("sol_anchor_zig", anchor_dep.module("sol_anchor_zig"));
        \\    b.installArtifact(program);
        \\
        \\    // IDL generator (native target for host machine)
        \\    const gen_idl = b.addExecutable(.{
        \\        .name = "gen_idl",
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/gen_idl.zig"),
        \\            .target = b.graph.host,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    gen_idl.root_module.addImport("solana_program_sdk", solana_dep.module("solana_program_sdk"));
        \\    gen_idl.root_module.addImport("sol_anchor_zig", anchor_dep.module("sol_anchor_zig"));
        \\
        \\    const run_gen_idl = b.addRunArtifact(gen_idl);
        \\    if (b.args) |args| {
        \\        run_gen_idl.addArgs(args);
        \\    }
        \\
        \\    const idl_step = b.step("idl", "Generate IDL JSON");
        \\    idl_step.dependOn(&run_gen_idl.step);
        \\
        \\    // Test step
        \\    const unit_tests = b.addTest(.{
        \\        .root_module = b.createModule(.{
        \\            .root_source_file = b.path("src/main.zig"),
        \\            .target = b.graph.host,
        \\            .optimize = optimize,
        \\        }),
        \\    });
        \\    unit_tests.root_module.addImport("solana_program_sdk", solana_dep.module("solana_program_sdk"));
        \\    unit_tests.root_module.addImport("sol_anchor_zig", anchor_dep.module("sol_anchor_zig"));
        \\
        \\    const run_tests = b.addRunArtifact(unit_tests);
        \\    const test_step = b.step("test", "Run unit tests");
        \\    test_step.dependOn(&run_tests.step);
        \\}
        \\
    ;
}

fn getBuildZonTemplate() []const u8 {
    return
        \\.{
        \\    .name = .my_program,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x0,
        \\    .minimum_zig_version = "0.15.0",
        \\    .dependencies = .{
        \\        // Update these paths to point to your local copies or use git URLs
        \\        .solana_program_sdk = .{
        \\            .path = "../solana-program-sdk-zig",
        \\            // Or use git:
        \\            // .url = "https://github.com/solana/solana-program-sdk-zig/archive/refs/heads/main.tar.gz",
        \\            // .hash = "...",
        \\        },
        \\        .sol_anchor_zig = .{
        \\            .path = "../anchor-zig",
        \\            // Or use git:
        \\            // .url = "https://github.com/example/anchor-zig/archive/refs/heads/main.tar.gz",
        \\            // .hash = "...",
        \\        },
        \\    },
        \\    .paths = .{
        \\        "build.zig",
        \\        "build.zig.zon",
        \\        "src",
        \\    },
        \\}
        \\
    ;
}

fn getReadmeTemplate() []const u8 {
    return
        \\# My Program
        \\
        \\Solana program built with anchor-zig.
        \\
        \\## Prerequisites
        \\
        \\- Zig 0.15.x
        \\- Solana CLI tools
        \\- anchor-zig and solana-program-sdk-zig
        \\
        \\## Build
        \\
        \\```bash
        \\# Build the program
        \\zig build
        \\
        \\# Generate IDL
        \\zig build idl
        \\
        \\# Run tests
        \\zig build test
        \\```
        \\
        \\## Deploy
        \\
        \\```bash
        \\# Deploy to devnet
        \\solana program deploy zig-out/bin/program.so --url devnet
        \\
        \\# Deploy to mainnet
        \\solana program deploy zig-out/bin/program.so --url mainnet-beta
        \\```
        \\
        \\## Project Structure
        \\
        \\```
        \\.
        \\├── src/
        \\│   ├── main.zig      # Main program code
        \\│   └── gen_idl.zig   # IDL generator
        \\├── idl/              # Generated IDL files
        \\├── client/           # Client SDK (TypeScript/JavaScript)
        \\├── tests/            # Integration tests
        \\├── target/           # Deployment artifacts
        \\├── build.zig         # Build configuration
        \\├── build.zig.zon     # Dependencies
        \\├── Anchor.toml       # Anchor configuration
        \\└── README.md
        \\```
        \\
        \\## IDL
        \\
        \\The IDL is generated from your Zig code and is Anchor-compatible.
        \\After running `zig build idl`, you'll find `idl/program.json`.
        \\
        \\## License
        \\
        \\MIT
        \\
    ;
}

fn getGitignoreTemplate() []const u8 {
    return
        \\# Zig
        \\zig-out/
        \\.zig-cache/
        \\
        \\# Solana
        \\target/deploy/
        \\*.so
        \\
        \\# Node
        \\node_modules/
        \\
        \\# IDE
        \\.vscode/
        \\.idea/
        \\
        \\# OS
        \\.DS_Store
        \\Thumbs.db
        \\
        \\# Secrets
        \\*.pem
        \\*.key
        \\keypair.json
        \\
    ;
}

fn getAnchorTomlTemplate() []const u8 {
    return
        \\[features]
        \\seeds = false
        \\skip-lint = false
        \\
        \\[programs.localnet]
        \\my_program = "11111111111111111111111111111111"
        \\
        \\[programs.devnet]
        \\my_program = "11111111111111111111111111111111"
        \\
        \\[registry]
        \\url = "https://api.apr.dev"
        \\
        \\[provider]
        \\cluster = "localnet"
        \\wallet = "~/.config/solana/id.json"
        \\
        \\[scripts]
        \\build = "zig build"
        \\test = "zig build test"
        \\idl = "zig build idl"
        \\
    ;
}

// ============================================================================
// idl Command
// ============================================================================

fn cmdIdl(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (args.len == 0) {
        try printIdlHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "-h") or std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "help")) {
        try printIdlHelp();
    } else if (std.mem.eql(u8, subcommand, "generate") or std.mem.eql(u8, subcommand, "gen")) {
        try cmdIdlGenerate(args[1..]);
    } else if (std.mem.eql(u8, subcommand, "init")) {
        try cmdIdlInit();
    } else if (std.mem.eql(u8, subcommand, "fetch")) {
        try cmdIdlFetch(args[1..]);
    } else {
        try printError("Unknown idl subcommand: {s}", .{subcommand});
        try printIdlHelp();
    }
}

fn printIdlHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig idl - IDL generation utilities
        \\
        \\USAGE:
        \\    anchor-zig idl <SUBCOMMAND> [OPTIONS]
        \\
        \\SUBCOMMANDS:
        \\    generate    Generate IDL from program definition
        \\    init        Create gen_idl.zig template
        \\    fetch       Fetch IDL from on-chain program
        \\    help        Show this help message
        \\
        \\EXAMPLES:
        \\    anchor-zig idl generate
        \\    anchor-zig idl generate -o custom/path/idl.json
        \\    anchor-zig idl init
        \\    anchor-zig idl fetch <PROGRAM_ID>
        \\
        \\NOTES:
        \\    The 'generate' command runs 'zig build idl' in the current directory.
        \\    Make sure your build.zig has an 'idl' step configured.
        \\
    , .{});
    try out.flush();
}

fn cmdIdlGenerate(args: []const []const u8) !void {
    var output_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            try printIdlGenerateHelp();
            return;
        } else if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            }
        }
    }

    try printInfo("Generating IDL...", .{});

    // Run zig build idl
    var argv_buf: [16][]const u8 = undefined;
    var argc: usize = 0;

    argv_buf[argc] = "zig";
    argc += 1;
    argv_buf[argc] = "build";
    argc += 1;
    argv_buf[argc] = "idl";
    argc += 1;

    if (output_path) |path| {
        argv_buf[argc] = "--";
        argc += 1;
        argv_buf[argc] = "-o";
        argc += 1;
        argv_buf[argc] = path;
        argc += 1;
    }

    var child = std.process.Child.init(argv_buf[0..argc], std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    _ = try child.spawnAndWait();
}

fn printIdlGenerateHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig idl generate - Generate IDL from program
        \\
        \\USAGE:
        \\    anchor-zig idl generate [OPTIONS]
        \\
        \\OPTIONS:
        \\    -o, --output <path>    Output path for IDL JSON
        \\    -h, --help             Show this help message
        \\
        \\EXAMPLES:
        \\    anchor-zig idl generate
        \\    anchor-zig idl generate -o idl/my_program.json
        \\
    , .{});
    try out.flush();
}

fn cmdIdlInit() !void {
    const cwd = std.fs.cwd();

    // Check if src/gen_idl.zig already exists
    cwd.access("src/gen_idl.zig", .{}) catch {
        // File doesn't exist, create it
        var dir = cwd.openDir("src", .{}) catch {
            try printError("src/ directory not found. Are you in a project directory?", .{});
            return;
        };
        defer dir.close();

        var file = try dir.createFile("gen_idl.zig", .{});
        defer file.close();
        try file.writeAll(getGenIdlTemplate());

        try printInfo("✅ Created src/gen_idl.zig", .{});
        try printInfo("", .{});
        try printInfo("Next: Add 'idl' step to your build.zig", .{});
        return;
    };

    try printError("src/gen_idl.zig already exists", .{});
}

fn cmdIdlFetch(args: []const []const u8) !void {
    if (args.len == 0) {
        try printError("Missing program ID", .{});
        try printInfo("Usage: anchor-zig idl fetch <PROGRAM_ID>", .{});
        return;
    }

    const program_id = args[0];
    try printInfo("Fetching IDL for program: {s}", .{program_id});
    try printInfo("Note: This feature requires anchor CLI or RPC access", .{});

    // TODO: Implement IDL fetching via RPC
    try printError("IDL fetch not yet implemented", .{});
}

// ============================================================================
// build Command
// ============================================================================

fn cmdBuild(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    var release = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printBuildHelp();
            return;
        } else if (std.mem.eql(u8, arg, "--release") or std.mem.eql(u8, arg, "-r")) {
            release = true;
        }
    }

    try printInfo("Building program...", .{});

    // Run zig build
    var argv_buf: [8][]const u8 = undefined;
    var argc: usize = 0;

    argv_buf[argc] = "zig";
    argc += 1;
    argv_buf[argc] = "build";
    argc += 1;

    if (release) {
        argv_buf[argc] = "-Doptimize=ReleaseFast";
        argc += 1;
    }

    var child = std.process.Child.init(argv_buf[0..argc], std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => |code| {
            if (code == 0) {
                try printInfo("✅ Build complete", .{});
                try printInfo("Output: zig-out/bin/program.so", .{});
            } else {
                try printError("Build failed with exit code: {d}", .{code});
            }
        },
        else => {
            try printError("Build process terminated abnormally", .{});
        },
    }
}

fn printBuildHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig build - Build the Solana program
        \\
        \\USAGE:
        \\    anchor-zig build [OPTIONS]
        \\
        \\OPTIONS:
        \\    -r, --release     Build with release optimizations
        \\    -h, --help        Show this help message
        \\
        \\This command runs 'zig build' in the current directory.
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// test Command
// ============================================================================

fn cmdTest(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printTestHelp();
            return;
        }
    }

    try printInfo("Running tests...", .{});

    // Run zig build test
    const argv = [_][]const u8{ "zig", "build", "test" };
    var child = std.process.Child.init(&argv, std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => |code| {
            if (code == 0) {
                try printInfo("✅ All tests passed", .{});
            } else {
                try printError("Tests failed with exit code: {d}", .{code});
            }
        },
        else => {
            try printError("Test process terminated abnormally", .{});
        },
    }
}

fn printTestHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig test - Run program tests
        \\
        \\USAGE:
        \\    anchor-zig test [OPTIONS]
        \\
        \\OPTIONS:
        \\    -h, --help    Show this help message
        \\
        \\This command runs 'zig build test' in the current directory.
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// deploy Command
// ============================================================================

fn cmdDeploy(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    var network: []const u8 = "localnet";
    var keypair_path: ?[]const u8 = null;
    var program_path: []const u8 = "zig-out/bin/program.so";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            try printDeployHelp();
            return;
        } else if (std.mem.eql(u8, args[i], "--network") or std.mem.eql(u8, args[i], "-n")) {
            i += 1;
            if (i < args.len) {
                network = args[i];
            }
        } else if (std.mem.eql(u8, args[i], "--keypair") or std.mem.eql(u8, args[i], "-k")) {
            i += 1;
            if (i < args.len) {
                keypair_path = args[i];
            }
        } else if (std.mem.eql(u8, args[i], "--program") or std.mem.eql(u8, args[i], "-p")) {
            i += 1;
            if (i < args.len) {
                program_path = args[i];
            }
        }
    }

    // Get RPC URL based on network
    const rpc_url = getNetworkUrl(network);

    try printInfo("Deploying program to {s}...", .{network});
    try printInfo("  Program: {s}", .{program_path});
    try printInfo("  RPC URL: {s}", .{rpc_url});

    // Check if program file exists
    std.fs.cwd().access(program_path, .{}) catch {
        try printError("Program file not found: {s}", .{program_path});
        try printInfo("Run 'anchor-zig build' first", .{});
        return;
    };

    // Build deploy command
    var argv_buf: [16][]const u8 = undefined;
    var argc: usize = 0;

    argv_buf[argc] = "solana";
    argc += 1;
    argv_buf[argc] = "program";
    argc += 1;
    argv_buf[argc] = "deploy";
    argc += 1;
    argv_buf[argc] = program_path;
    argc += 1;
    argv_buf[argc] = "--url";
    argc += 1;
    argv_buf[argc] = rpc_url;
    argc += 1;

    if (keypair_path) |kp| {
        argv_buf[argc] = "--keypair";
        argc += 1;
        argv_buf[argc] = kp;
        argc += 1;
    }

    var child = std.process.Child.init(argv_buf[0..argc], std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => |code| {
            if (code == 0) {
                try printInfo("✅ Deploy complete", .{});
            } else {
                try printError("Deploy failed with exit code: {d}", .{code});
            }
        },
        else => {
            try printError("Deploy process terminated abnormally", .{});
        },
    }
}

fn getNetworkUrl(network: []const u8) []const u8 {
    if (std.mem.eql(u8, network, "mainnet") or std.mem.eql(u8, network, "mainnet-beta")) {
        return "https://api.mainnet-beta.solana.com";
    } else if (std.mem.eql(u8, network, "devnet")) {
        return "https://api.devnet.solana.com";
    } else if (std.mem.eql(u8, network, "testnet")) {
        return "https://api.testnet.solana.com";
    } else {
        return "http://localhost:8899";
    }
}

fn printDeployHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig deploy - Deploy program to network
        \\
        \\USAGE:
        \\    anchor-zig deploy [OPTIONS]
        \\
        \\OPTIONS:
        \\    -n, --network <name>     Network to deploy to (localnet, devnet, testnet, mainnet)
        \\    -k, --keypair <path>     Path to keypair file
        \\    -p, --program <path>     Path to program .so file
        \\    -h, --help               Show this help message
        \\
        \\NETWORKS:
        \\    localnet    Local validator (http://localhost:8899)
        \\    devnet      Solana Devnet
        \\    testnet     Solana Testnet
        \\    mainnet     Solana Mainnet Beta
        \\
        \\EXAMPLES:
        \\    anchor-zig deploy
        \\    anchor-zig deploy --network devnet
        \\    anchor-zig deploy --network mainnet --keypair ~/.config/solana/deploy.json
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// verify Command
// ============================================================================

fn cmdVerify(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    var program_id: ?[]const u8 = null;
    var network: []const u8 = "mainnet";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            try printVerifyHelp();
            return;
        } else if (std.mem.eql(u8, args[i], "--network") or std.mem.eql(u8, args[i], "-n")) {
            i += 1;
            if (i < args.len) {
                network = args[i];
            }
        } else {
            program_id = args[i];
        }
    }

    if (program_id == null) {
        try printError("Missing program ID", .{});
        try printVerifyHelp();
        return;
    }

    try printInfo("Verifying program: {s}", .{program_id.?});
    try printInfo("Network: {s}", .{network});

    // TODO: Implement program verification
    try printError("Program verification not yet implemented", .{});
    try printInfo("This feature will compare deployed bytecode with local build", .{});
}

fn printVerifyHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig verify - Verify deployed program
        \\
        \\USAGE:
        \\    anchor-zig verify <PROGRAM_ID> [OPTIONS]
        \\
        \\ARGUMENTS:
        \\    <PROGRAM_ID>    Program ID to verify
        \\
        \\OPTIONS:
        \\    -n, --network <name>    Network to verify on (default: mainnet)
        \\    -h, --help              Show this help message
        \\
        \\EXAMPLES:
        \\    anchor-zig verify TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA
        \\    anchor-zig verify <program-id> --network devnet
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// keys Command
// ============================================================================

fn cmdKeys(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    if (args.len == 0) {
        try printKeysHelp();
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "-h") or std.mem.eql(u8, subcommand, "--help") or std.mem.eql(u8, subcommand, "help")) {
        try printKeysHelp();
    } else if (std.mem.eql(u8, subcommand, "generate") or std.mem.eql(u8, subcommand, "new")) {
        try cmdKeysGenerate(args[1..]);
    } else if (std.mem.eql(u8, subcommand, "show")) {
        try cmdKeysShow(args[1..]);
    } else {
        try printError("Unknown keys subcommand: {s}", .{subcommand});
        try printKeysHelp();
    }
}

fn printKeysHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig keys - Keypair management
        \\
        \\USAGE:
        \\    anchor-zig keys <SUBCOMMAND> [OPTIONS]
        \\
        \\SUBCOMMANDS:
        \\    generate    Generate a new keypair
        \\    show        Show public key from keypair file
        \\    help        Show this help message
        \\
        \\EXAMPLES:
        \\    anchor-zig keys generate
        \\    anchor-zig keys generate -o program-keypair.json
        \\    anchor-zig keys show keypair.json
        \\
    , .{});
    try out.flush();
}

fn cmdKeysGenerate(args: []const []const u8) !void {
    var output_path: []const u8 = "keypair.json";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-h") or std.mem.eql(u8, args[i], "--help")) {
            var impl = std.fs.File.stdout().writer(&stdout_buffer);
            const out: *std.Io.Writer = &impl.interface;
            try out.print(
                \\
                \\anchor-zig keys generate - Generate a new keypair
                \\
                \\USAGE:
                \\    anchor-zig keys generate [OPTIONS]
                \\
                \\OPTIONS:
                \\    -o, --output <path>    Output path for keypair (default: keypair.json)
                \\    -h, --help             Show this help message
                \\
            , .{});
            try out.flush();
            return;
        } else if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            }
        }
    }

    try printInfo("Generating new keypair...", .{});

    // Use solana-keygen
    const argv = [_][]const u8{ "solana-keygen", "new", "--outfile", output_path, "--no-bip39-passphrase" };
    var child = std.process.Child.init(&argv, std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    const result = try child.spawnAndWait();
    switch (result) {
        .Exited => |code| {
            if (code == 0) {
                try printInfo("✅ Keypair saved to: {s}", .{output_path});
            } else {
                try printError("Keypair generation failed", .{});
            }
        },
        else => {
            try printError("Keypair generation process terminated abnormally", .{});
        },
    }
}

fn cmdKeysShow(args: []const []const u8) !void {
    if (args.len == 0) {
        try printError("Missing keypair file path", .{});
        try printInfo("Usage: anchor-zig keys show <keypair.json>", .{});
        return;
    }

    const keypair_path = args[0];

    // Use solana-keygen to show public key
    const argv = [_][]const u8{ "solana-keygen", "pubkey", keypair_path };
    var child = std.process.Child.init(&argv, std.heap.page_allocator);
    child.stderr_behavior = .Inherit;
    child.stdout_behavior = .Inherit;

    _ = try child.spawnAndWait();
}

// ============================================================================
// clean Command
// ============================================================================

fn cmdClean(allocator: Allocator, args: []const []const u8) !void {
    _ = allocator;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            try printCleanHelp();
            return;
        }
    }

    try printInfo("Cleaning build artifacts...", .{});

    const cwd = std.fs.cwd();

    // Remove zig-out
    cwd.deleteTree("zig-out") catch |err| {
        try printError("Failed to remove zig-out: {s}", .{@errorName(err)});
    };
    try printInfo("  Removed zig-out/", .{});

    // Remove .zig-cache
    cwd.deleteTree(".zig-cache") catch |err| {
        try printError("Failed to remove .zig-cache: {s}", .{@errorName(err)});
    };
    try printInfo("  Removed .zig-cache/", .{});

    try printInfo("✅ Clean complete", .{});
}

fn printCleanHelp() !void {
    var impl = std.fs.File.stdout().writer(&stdout_buffer);
    const out: *std.Io.Writer = &impl.interface;
    try out.print(
        \\
        \\anchor-zig clean - Clean build artifacts
        \\
        \\USAGE:
        \\    anchor-zig clean [OPTIONS]
        \\
        \\OPTIONS:
        \\    -h, --help    Show this help message
        \\
        \\This command removes zig-out/ and .zig-cache/ directories.
        \\
    , .{});
    try out.flush();
}

// ============================================================================
// Tests
// ============================================================================

test "getNetworkUrl" {
    const testing = std.testing;
    try testing.expectEqualStrings("https://api.mainnet-beta.solana.com", getNetworkUrl("mainnet"));
    try testing.expectEqualStrings("https://api.mainnet-beta.solana.com", getNetworkUrl("mainnet-beta"));
    try testing.expectEqualStrings("https://api.devnet.solana.com", getNetworkUrl("devnet"));
    try testing.expectEqualStrings("https://api.testnet.solana.com", getNetworkUrl("testnet"));
    try testing.expectEqualStrings("http://localhost:8899", getNetworkUrl("localnet"));
    try testing.expectEqualStrings("http://localhost:8899", getNetworkUrl("unknown"));
}
