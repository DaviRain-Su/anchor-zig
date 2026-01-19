const std = @import("std");
const solana = @import("solana_program_sdk");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const target = b.resolveTargetQuery(solana.sbf_target);

    const sdk_dep = b.dependency("solana_program_sdk", .{
        .target = target,
        .optimize = optimize,
    });
    const sdk_mod = sdk_dep.module("solana_program_sdk");

    const program = b.addLibrary(.{
        .name = "spl_token",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    program.root_module.addImport("solana_program_sdk", sdk_mod);

    _ = solana.buildProgram(b, program, target, optimize);
    b.installArtifact(program);
}
