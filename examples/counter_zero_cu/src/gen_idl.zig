//! IDL Generator for Counter Program
//!
//! Generates Anchor-compatible IDL JSON file.
//!
//! Usage:
//!   zig build idl
//!   # Output: target/idl/counter.json

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const idl = anchor.idl_zero;

// Import program definition
const main = @import("main.zig");
const Program = main.Program;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line args for output path
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var output_path: []const u8 = "target/idl/counter.json";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
            i += 1;
            if (i < args.len) {
                output_path = args[i];
            }
        }
    }

    // Generate and write IDL
    try idl.writeJsonFile(allocator, Program, output_path);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Generated IDL: {s}\n", .{output_path});
}
