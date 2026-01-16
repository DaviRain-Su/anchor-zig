const std = @import("std");
const solana = @import("solana_program_sdk");

pub fn build(b: *std.Build) void {
    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Prioritize performance, safety, or binary size") orelse .ReleaseSmall;
    const target = b.resolveTargetQuery(solana.sbf_target);

    const sdk_dep = b.dependency("solana_program_sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const sdk_mod = sdk_dep.module("solana_program_sdk");

    const anchor_dep = b.dependency("sol_anchor_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const anchor_mod = anchor_dep.module("sol_anchor_zig");

    const sdk_host_dep = b.dependency("solana_program_sdk", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const sdk_host_mod = sdk_host_dep.module("solana_program_sdk");

    const anchor_host_dep = b.dependency("sol_anchor_zig", .{
        .target = b.graph.host,
        .optimize = optimize,
    });
    const anchor_host_mod = anchor_host_dep.module("sol_anchor_zig");

    const program_name = b.option([]const u8, "program-name", "Program artifact name") orelse "anchor_program";

    const program = b.addLibrary(.{
        .name = program_name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    program.root_module.addImport("solana_program_sdk", sdk_mod);
    program.root_module.addImport("sol_anchor_zig", anchor_mod);

    _ = solana.buildProgram(b, program, target, optimize);
    b.installArtifact(program);

    const idl_program_path = b.option([]const u8, "idl-program", "Program module path for IDL generation") orelse "src/main.zig";
    const idl_output_dir = b.option([]const u8, "idl-output-dir", "IDL output directory") orelse "idl";
    const idl_output_path = b.option([]const u8, "idl-output", "IDL output path (overrides idl-output-dir)") orelse "";

    const idl_options = b.addOptions();
    idl_options.addOption([]const u8, "idl_output_dir", idl_output_dir);
    idl_options.addOption([]const u8, "idl_output_path", idl_output_path);

    const idl_program_mod = b.createModule(.{
        .root_source_file = b.path(idl_program_path),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "solana_program_sdk", .module = sdk_host_mod },
            .{ .name = "sol_anchor_zig", .module = anchor_host_mod },
        },
    });

    const idl_exe = b.addExecutable(.{
        .name = "anchor-idl",
        .root_module = b.createModule(.{
            .root_source_file = anchor_host_dep.path("src/idl_cli.zig"),
            .target = b.graph.host,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "solana_program_sdk", .module = sdk_host_mod },
                .{ .name = "sol_anchor_zig", .module = anchor_host_mod },
                .{ .name = "idl_program", .module = idl_program_mod },
            },
        }),
    });
    idl_exe.root_module.addOptions("build_options", idl_options);

    const run_idl = b.addRunArtifact(idl_exe);
    const idl_step = b.step("idl", "Generate Anchor IDL JSON");
    idl_step.dependOn(&run_idl.step);
}
