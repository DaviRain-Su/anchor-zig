//! Anchor IDL JSON generator CLI
//!
//! Rust source: https://github.com/coral-xyz/anchor/blob/master/cli/src/lib.rs
//!
//! This tool writes Anchor-compatible IDL JSON to an output path.

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const build_options = @import("build_options");
const program_mod = @import("idl_program");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const output_dir = if (build_options.idl_output_dir.len == 0) "." else build_options.idl_output_dir;
    const output_path = try resolveOutputPath(allocator, output_dir, build_options.idl_output_path);
    defer allocator.free(output_path);
    try anchor.idl.writeJsonFile(allocator, program_mod.Program, .{}, output_path);
}

fn resolveOutputPath(allocator: std.mem.Allocator, output_dir: []const u8, output_path: []const u8) ![]u8 {
    if (output_path.len != 0) {
        return allocator.dupe(u8, output_path);
    }
    const name = anchor.idl.defaultIdlName(program_mod.Program);
    const file_stem = try toSnakeCase(allocator, name);
    defer allocator.free(file_stem);
    return std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ output_dir, file_stem });
}

fn toSnakeCase(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, name.len + 8);
    errdefer out.deinit(allocator);

    var prev_is_lower_or_digit = false;
    for (name) |ch| {
        if (std.ascii.isUpper(ch)) {
            if (prev_is_lower_or_digit) {
                try out.append(allocator, '_');
            }
            try out.append(allocator, std.ascii.toLower(ch));
            prev_is_lower_or_digit = true;
            continue;
        }

        if (ch == '-' or ch == ' ') {
            if (out.items.len == 0 or out.items[out.items.len - 1] == '_') {
                continue;
            }
            try out.append(allocator, '_');
            prev_is_lower_or_digit = false;
            continue;
        }

        try out.append(allocator, std.ascii.toLower(ch));
        prev_is_lower_or_digit = std.ascii.isLower(ch) or std.ascii.isDigit(ch);
    }

    return try out.toOwnedSlice(allocator);
}
