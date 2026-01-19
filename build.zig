const std = @import("std");
const solana = @import("solana_program_sdk");

pub fn build(b: *std.Build) void {
    // Accept target and optimize options from dependents
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Use provided target or default to SBF for Solana programs
    const sbf_target = b.resolveTargetQuery(solana.sbf_target);
    const effective_target = if (target.result.cpu.arch == .x86_64 or target.result.cpu.arch == .aarch64)
        target
    else
        sbf_target;

    // Get dependencies for effective target
    const solana_dep = b.dependency("solana_program_sdk", .{
        .target = effective_target,
        .optimize = optimize,
    });
    const solana_mod = solana_dep.module("solana_program_sdk");

    // Main anchor module
    const anchor_mod = b.addModule("sol_anchor_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = effective_target,
        .optimize = optimize,
    });
    anchor_mod.addImport("solana_program_sdk", solana_mod);

    // Get dependencies for host target (for IDL generation and testing)
    const solana_host_dep = b.dependency("solana_program_sdk", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const solana_host_mod = solana_host_dep.module("solana_program_sdk");

    // Host module for IDL generation and testing
    const anchor_host_mod = b.addModule("sol_anchor_zig_host", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    anchor_host_mod.addImport("solana_program_sdk", solana_host_mod);

    // IDL CLI tool (template for generating IDL)
    // Users should create their own IDL generator that imports their program
    const idl_exe = b.addExecutable(.{
        .name = "anchor-idl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/idl_cli.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "solana_program_sdk", .module = solana_host_mod },
                .{ .name = "sol_anchor_zig", .module = anchor_host_mod },
            },
        }),
    });

    const run_idl = b.addRunArtifact(idl_exe);
    const idl_step = b.step("idl", "Show IDL generation instructions");
    idl_step.dependOn(&run_idl.step);

    // Unit tests (host target)
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    lib_unit_tests.root_module.addImport("solana_program_sdk", solana_host_mod);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
