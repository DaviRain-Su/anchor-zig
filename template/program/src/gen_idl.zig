//! IDL Generator
//!
//! Generates Anchor-compatible IDL JSON for TypeScript client.
//!
//! Build and run:
//!   zig build-exe src/gen_idl.zig -o gen_idl \
//!       --deps solana_program_sdk,sol_anchor_zig \
//!       -Msolana_program_sdk=path/to/sdk/src/root.zig \
//!       -Msol_anchor_zig=path/to/anchor-zig/src/root.zig
//!   ./gen_idl -o target/idl/my_program.json

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const idl = anchor.idl_zero;
const Program = @import("main.zig").Program;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_path: []const u8 = "target/idl/my_program.json";
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) output_path = args[i];
        }
    }

    try idl.writeJsonFile(allocator, Program, output_path);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("✅ Generated IDL: {s}\n", .{output_path});
}
