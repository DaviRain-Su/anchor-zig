const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{
        .default_target = @import("solana_program_sdk").sbf_target,
    });

    const solana_dep = b.dependency("solana_program_sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const solana_mod = solana_dep.module("solana_program_sdk");

    const anchor_mod = b.addModule("sol_anchor_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    anchor_mod.addImport("solana_program_sdk", solana_mod);

    const solana_host_dep = b.dependency("solana_program_sdk", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const solana_host_mod = solana_host_dep.module("solana_program_sdk");

    const anchor_host_mod = b.addModule("sol_anchor_zig_host", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    anchor_host_mod.addImport("solana_program_sdk", solana_host_mod);

    const idl_program_path = b.option([]const u8, "idl-program", "Program module path for IDL generation") orelse "src/idl_example.zig";
    const idl_output_path = b.option([]const u8, "idl-output", "IDL output path") orelse "idl/anchor.json";

    const idl_options = b.addOptions();
    idl_options.addOption([]const u8, "idl_output_path", idl_output_path);

    const idl_program_mod = b.createModule(.{
        .root_source_file = b.path(idl_program_path),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "solana_program_sdk", .module = solana_host_mod },
            .{ .name = "sol_anchor_zig", .module = anchor_host_mod },
        },
    });

    const idl_exe = b.addExecutable(.{
        .name = "anchor-idl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/idl_cli.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "solana_program_sdk", .module = solana_host_mod },
                .{ .name = "sol_anchor_zig", .module = anchor_host_mod },
                .{ .name = "idl_program", .module = idl_program_mod },
            },
        }),
    });
    idl_exe.root_module.addOptions("build_options", idl_options);

    const run_idl = b.addRunArtifact(idl_exe);
    const idl_step = b.step("idl", "Generate Anchor IDL JSON");
    idl_step.dependOn(&run_idl.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = anchor_mod,
    });
    lib_unit_tests.root_module.addImport("solana_program_sdk", solana_mod);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
