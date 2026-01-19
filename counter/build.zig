const std = @import("std");
const solana = @import("solana_program_sdk");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseFast;
    const target = b.resolveTargetQuery(solana.sbf_target);

    // ========================================
    // Dependencies
    // ========================================

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

    // ========================================
    // Main Program (SBF target)
    // ========================================

    const program = b.addLibrary(.{
        .name = "counter",
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

    // ========================================
    // IDL Generator (native target)
    // ========================================

    const native_sdk_dep = b.dependency("solana_program_sdk", .{});
    const native_sdk_mod = native_sdk_dep.module("solana_program_sdk");
    
    const native_anchor_dep = b.dependency("sol_anchor_zig", .{});
    const native_anchor_mod = native_anchor_dep.module("sol_anchor_zig");

    const idl_gen = b.addExecutable(.{
        .name = "gen_idl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/gen_idl.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
    idl_gen.root_module.addImport("solana_program_sdk", native_sdk_mod);
    idl_gen.root_module.addImport("sol_anchor_zig", native_anchor_mod);

    // Run step to generate IDL
    const run_idl = b.addRunArtifact(idl_gen);
    run_idl.addArgs(&.{ "-o", "idl/counter.json" });

    const idl_step = b.step("idl", "Generate IDL JSON");
    idl_step.dependOn(&run_idl.step);
}
