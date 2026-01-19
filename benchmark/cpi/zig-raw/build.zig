const std = @import("std");
const solana = @import("solana_program_sdk");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const target = b.resolveTargetQuery(solana.sbf_target);

    const lib_dep = b.dependency("solana_program_library", .{
        .target = target,
        .optimize = optimize,
    });
    const lib_mod = lib_dep.module("solana_program_library");

    const program = b.addLibrary(.{
        .name = "cpi_zig",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    program.root_module.addImport("solana_program_library", lib_mod);

    _ = solana.buildProgram(b, program, target, optimize);
    b.installArtifact(program);
}
