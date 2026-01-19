//! IDL Generation for zero_cu Programs
//!
//! Generates Anchor-compatible IDL JSON from zero_cu program definitions.
//! Compatible with @coral-xyz/anchor TypeScript client.
//!
//! ## Usage
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//! const idl = anchor.idl_zero;
//!
//! const CounterData = struct {
//!     count: u64,
//!     authority: sol.PublicKey,
//! };
//!
//! const IncrementAccounts = struct {
//!     authority: zero.Signer(0),
//!     counter: zero.Account(CounterData, .{ .owner = PROGRAM_ID }),
//! };
//!
//! pub const Program = struct {
//!     pub const id = sol.PublicKey.comptimeFromBase58("...");
//!     pub const name = "counter";
//!     pub const version = "0.1.0";
//!
//!     pub const instructions = .{
//!         idl.Instruction("increment", IncrementAccounts, void),
//!     };
//!
//!     pub const accounts = .{
//!         idl.AccountDef("Counter", CounterData),
//!     };
//!
//!     pub const errors = enum(u32) {
//!         InvalidAuthority = 6000,
//!         CounterOverflow = 6001,
//!     };
//! };
//!
//! // Generate IDL
//! const json = try idl.generateJson(allocator, Program);
//! ```

const std = @import("std");
const discriminator_mod = @import("discriminator.zig");
const zero_cu = @import("zero_cu.zig");
const sol = @import("solana_program_sdk");

const Allocator = std.mem.Allocator;
const PublicKey = sol.PublicKey;

// ============================================================================
// IDL Definition Types
// ============================================================================

/// Instruction definition for IDL
pub fn Instruction(
    comptime name: []const u8,
    comptime Accounts: type,
    comptime Args: type,
) type {
    return InstructionWithDocs(name, Accounts, Args, null);
}

/// Instruction definition with documentation
pub fn InstructionWithDocs(
    comptime name: []const u8,
    comptime Accounts: type,
    comptime Args: type,
    comptime docs: ?[]const u8,
) type {
    return struct {
        pub const instruction_name = name;
        pub const AccountsType = Accounts;
        pub const ArgsType = Args;
        pub const documentation = docs;
    };
}

/// Account definition for IDL
pub fn AccountDef(comptime name: []const u8, comptime Data: type) type {
    return AccountDefWithDocs(name, Data, null);
}

/// Account definition with documentation
pub fn AccountDefWithDocs(comptime name: []const u8, comptime Data: type, comptime docs: ?[]const u8) type {
    return struct {
        pub const account_name = name;
        pub const DataType = Data;
        pub const documentation = docs;
    };
}

/// Event definition for IDL
pub fn EventDef(comptime name: []const u8, comptime Data: type) type {
    return struct {
        pub const event_name = name;
        pub const DataType = Data;
    };
}

// ============================================================================
// IDL Generation
// ============================================================================

/// Generate Anchor-compatible IDL JSON
pub fn generateJson(allocator: Allocator, comptime program: anytype) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var type_registry = std.StringHashMap(void).init(a);
    var type_defs = std.json.Array.init(a);

    // Build root object
    var root = std.json.ObjectMap.init(a);

    // Address
    var address_buffer: [44]u8 = undefined;
    const address = program.id.toBase58(&address_buffer);
    try putString(a, &root, "address", address);

    // Metadata
    const metadata = try buildMetadata(a, program);
    try root.put(try a.dupe(u8, "metadata"), metadata);

    // Instructions
    const instructions = try buildInstructions(a, program, &type_registry, &type_defs);
    try root.put(try a.dupe(u8, "instructions"), instructions);

    // Accounts
    const accounts = try buildAccounts(a, program, &type_registry, &type_defs);
    try root.put(try a.dupe(u8, "accounts"), accounts);

    // Types
    try root.put(try a.dupe(u8, "types"), .{ .array = type_defs });

    // Errors
    const errors = try buildErrors(a, program);
    try root.put(try a.dupe(u8, "errors"), errors);

    // Events (optional)
    if (@hasDecl(program, "events")) {
        const events = try buildEvents(a, program, &type_registry, &type_defs);
        try root.put(try a.dupe(u8, "events"), events);
    }

    // Serialize to JSON
    const json = std.json.Value{ .object = root };
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try std.json.stringify(json, .{ .whitespace = .indent_2 }, out.writer());
    return try out.toOwnedSlice();
}

/// Write IDL JSON to file
pub fn writeJsonFile(
    allocator: Allocator,
    comptime program: anytype,
    output_path: []const u8,
) !void {
    const json = try generateJson(allocator, program);
    defer allocator.free(json);

    const dir = std.fs.path.dirname(output_path) orelse ".";
    try std.fs.cwd().makePath(dir);

    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(json);
}

// ============================================================================
// Internal Builders
// ============================================================================

fn buildMetadata(a: Allocator, comptime program: anytype) !std.json.Value {
    var obj = std.json.ObjectMap.init(a);

    const name = if (@hasDecl(program, "name")) program.name else "unknown";
    const version = if (@hasDecl(program, "version")) program.version else "0.1.0";
    const spec = if (@hasDecl(program, "spec")) program.spec else "0.1.0";

    try putString(a, &obj, "name", name);
    try putString(a, &obj, "version", version);
    try putString(a, &obj, "spec", spec);

    return .{ .object = obj };
}

fn buildInstructions(
    a: Allocator,
    comptime program: anytype,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var arr = std.json.Array.init(a);

    if (@hasDecl(program, "instructions")) {
        const instructions = program.instructions;
        inline for (instructions) |InstrType| {
            const ix = try buildInstruction(a, InstrType, type_registry, type_defs);
            try arr.append(ix);
        }
    }

    return .{ .array = arr };
}

fn buildInstruction(
    a: Allocator,
    comptime InstrType: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var obj = std.json.ObjectMap.init(a);

    const name = InstrType.instruction_name;
    try putString(a, &obj, "name", name);

    // Documentation
    if (@hasDecl(InstrType, "documentation") and InstrType.documentation != null) {
        var docs = std.json.Array.init(a);
        try docs.append(jsonString(a, InstrType.documentation.?));
        try obj.put(try a.dupe(u8, "docs"), .{ .array = docs });
    }

    // Discriminator
    const disc = comptime discriminator_mod.instructionDiscriminator(name);
    try obj.put(try a.dupe(u8, "discriminator"), try discriminatorJson(a, disc));

    // Accounts
    const accounts = try buildInstructionAccounts(a, InstrType.AccountsType);
    try obj.put(try a.dupe(u8, "accounts"), accounts);

    // Args
    const args = try buildArgs(a, InstrType.ArgsType, type_registry, type_defs);
    try obj.put(try a.dupe(u8, "args"), args);

    return .{ .object = obj };
}

fn buildInstructionAccounts(a: Allocator, comptime Accounts: type) !std.json.Value {
    var arr = std.json.Array.init(a);

    const fields = std.meta.fields(Accounts);
    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(a);

        try putString(a, &obj, "name", field.name);

        // Determine account properties from zero_cu type
        const is_signer = if (@hasDecl(field.type, "is_signer")) field.type.is_signer else false;
        const is_writable = if (@hasDecl(field.type, "is_writable")) field.type.is_writable else false;

        try obj.put(try a.dupe(u8, "writable"), .{ .bool = is_writable });
        try obj.put(try a.dupe(u8, "signer"), .{ .bool = is_signer });

        // Optional constraints description
        if (@hasDecl(field.type, "CONSTRAINTS")) {
            const C = field.type.CONSTRAINTS;

            // Add PDA info if present
            if (C.seeds != null) {
                var pda_obj = std.json.ObjectMap.init(a);
                var seeds_arr = std.json.Array.init(a);

                inline for (C.seeds.?) |seed| {
                    var seed_obj = std.json.ObjectMap.init(a);
                    switch (seed) {
                        .literal => |lit| {
                            try putString(a, &seed_obj, "kind", "const");
                            try putString(a, &seed_obj, "value", lit);
                        },
                        .account => |acc| {
                            try putString(a, &seed_obj, "kind", "account");
                            try putString(a, &seed_obj, "path", acc);
                        },
                        .field => |fld| {
                            try putString(a, &seed_obj, "kind", "field");
                            try putString(a, &seed_obj, "path", fld);
                        },
                        .bump => {
                            try putString(a, &seed_obj, "kind", "bump");
                        },
                    }
                    try seeds_arr.append(.{ .object = seed_obj });
                }

                try pda_obj.put(try a.dupe(u8, "seeds"), .{ .array = seeds_arr });
                try obj.put(try a.dupe(u8, "pda"), .{ .object = pda_obj });
            }

            // Add relations (has_one)
            if (C.has_one != null) {
                var relations = std.json.Array.init(a);
                inline for (C.has_one.?) |rel| {
                    try relations.append(jsonString(a, rel));
                }
                try obj.put(try a.dupe(u8, "relations"), .{ .array = relations });
            }

            // Add optional flag
            if (@hasDecl(field.type, "is_optional") and field.type.is_optional) {
                try obj.put(try a.dupe(u8, "optional"), .{ .bool = true });
            }
        }

        try arr.append(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn buildArgs(
    a: Allocator,
    comptime Args: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var arr = std.json.Array.init(a);

    if (Args == void) {
        return .{ .array = arr };
    }

    const fields = std.meta.fields(Args);
    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(a);
        try putString(a, &obj, "name", field.name);
        try obj.put(try a.dupe(u8, "type"), try typeToJson(a, field.type, type_registry, type_defs));
        try arr.append(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn buildAccounts(
    a: Allocator,
    comptime program: anytype,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var arr = std.json.Array.init(a);

    if (@hasDecl(program, "accounts")) {
        const accounts = program.accounts;
        inline for (accounts) |AccType| {
            const acc = try buildAccountDef(a, AccType, type_registry, type_defs);
            try arr.append(acc);
        }
    }

    return .{ .array = arr };
}

fn buildAccountDef(
    a: Allocator,
    comptime AccType: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var obj = std.json.ObjectMap.init(a);

    const name = AccType.account_name;
    try putString(a, &obj, "name", name);

    // Discriminator
    const disc = comptime discriminator_mod.accountDiscriminator(name);
    try obj.put(try a.dupe(u8, "discriminator"), try discriminatorJson(a, disc));

    // Type reference
    try registerType(a, AccType.DataType, type_registry, type_defs);
    const type_name = @typeName(AccType.DataType);
    const short_name = shortTypeName(type_name);
    var type_obj = std.json.ObjectMap.init(a);
    try putString(a, &type_obj, "defined", .{ .name = short_name });
    try obj.put(try a.dupe(u8, "type"), .{ .object = type_obj });

    return .{ .object = obj };
}

fn buildErrors(a: Allocator, comptime program: anytype) !std.json.Value {
    var arr = std.json.Array.init(a);

    if (@hasDecl(program, "errors")) {
        const Errors = @TypeOf(program.errors);
        const info = @typeInfo(Errors);
        if (info == .@"enum") {
            inline for (info.@"enum".fields) |field| {
                var obj = std.json.ObjectMap.init(a);
                const code = @intFromEnum(@field(Errors, field.name));
                try putString(a, &obj, "name", field.name);
                try obj.put(try a.dupe(u8, "code"), .{ .integer = @intCast(code) });
                try arr.append(.{ .object = obj });
            }
        }
    }

    return .{ .array = arr };
}

fn buildEvents(
    a: Allocator,
    comptime program: anytype,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var arr = std.json.Array.init(a);

    if (@hasDecl(program, "events")) {
        const events = program.events;
        inline for (events) |EvtType| {
            var obj = std.json.ObjectMap.init(a);
            const name = EvtType.event_name;
            try putString(a, &obj, "name", name);

            // Discriminator
            const disc = comptime discriminator_mod.sighash("event", name);
            try obj.put(try a.dupe(u8, "discriminator"), try discriminatorJson(a, disc));

            // Fields
            try registerType(a, EvtType.DataType, type_registry, type_defs);
            const fields = try buildTypeFields(a, EvtType.DataType, type_registry, type_defs);
            try obj.put(try a.dupe(u8, "fields"), fields);

            try arr.append(.{ .object = obj });
        }
    }

    return .{ .array = arr };
}

// ============================================================================
// Type Conversion
// ============================================================================

fn typeToJson(
    a: Allocator,
    comptime T: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    const info = @typeInfo(T);

    // Primitive types
    if (T == bool) return jsonString(a, "bool");
    if (T == u8) return jsonString(a, "u8");
    if (T == u16) return jsonString(a, "u16");
    if (T == u32) return jsonString(a, "u32");
    if (T == u64) return jsonString(a, "u64");
    if (T == u128) return jsonString(a, "u128");
    if (T == i8) return jsonString(a, "i8");
    if (T == i16) return jsonString(a, "i16");
    if (T == i32) return jsonString(a, "i32");
    if (T == i64) return jsonString(a, "i64");
    if (T == i128) return jsonString(a, "i128");

    // PublicKey
    if (T == PublicKey) return jsonString(a, "pubkey");

    // Arrays
    if (info == .array) {
        const child = info.array.child;
        if (child == u8) {
            // [N]u8 -> bytes
            var obj = std.json.ObjectMap.init(a);
            var arr_obj = std.json.ObjectMap.init(a);
            try putString(a, &arr_obj, "bytes", null);
            try arr_obj.put(try a.dupe(u8, "size"), .{ .integer = info.array.len });
            try obj.put(try a.dupe(u8, "array"), .{ .object = arr_obj });
            return .{ .object = obj };
        } else {
            // [N]T -> array
            var obj = std.json.ObjectMap.init(a);
            var arr_obj = std.json.ObjectMap.init(a);
            try arr_obj.put(try a.dupe(u8, "element"), try typeToJson(a, child, type_registry, type_defs));
            try arr_obj.put(try a.dupe(u8, "size"), .{ .integer = info.array.len });
            try obj.put(try a.dupe(u8, "array"), .{ .object = arr_obj });
            return .{ .object = obj };
        }
    }

    // Slices
    if (info == .pointer and info.pointer.size == .Slice) {
        var obj = std.json.ObjectMap.init(a);
        try obj.put(try a.dupe(u8, "vec"), try typeToJson(a, info.pointer.child, type_registry, type_defs));
        return .{ .object = obj };
    }

    // Optional
    if (info == .optional) {
        var obj = std.json.ObjectMap.init(a);
        try obj.put(try a.dupe(u8, "option"), try typeToJson(a, info.optional.child, type_registry, type_defs));
        return .{ .object = obj };
    }

    // Struct (defined type)
    if (info == .@"struct") {
        try registerType(a, T, type_registry, type_defs);
        const type_name = @typeName(T);
        const short_name = shortTypeName(type_name);
        var obj = std.json.ObjectMap.init(a);
        var def_obj = std.json.ObjectMap.init(a);
        try putString(a, &def_obj, "name", short_name);
        try obj.put(try a.dupe(u8, "defined"), .{ .object = def_obj });
        return .{ .object = obj };
    }

    // Enum (simple)
    if (info == .@"enum") {
        try registerType(a, T, type_registry, type_defs);
        const type_name = @typeName(T);
        const short_name = shortTypeName(type_name);
        var obj = std.json.ObjectMap.init(a);
        var def_obj = std.json.ObjectMap.init(a);
        try putString(a, &def_obj, "name", short_name);
        try obj.put(try a.dupe(u8, "defined"), .{ .object = def_obj });
        return .{ .object = obj };
    }

    // Union (Rust enum with data)
    if (info == .@"union") {
        try registerType(a, T, type_registry, type_defs);
        const type_name = @typeName(T);
        const short_name = shortTypeName(type_name);
        var obj = std.json.ObjectMap.init(a);
        var def_obj = std.json.ObjectMap.init(a);
        try putString(a, &def_obj, "name", short_name);
        try obj.put(try a.dupe(u8, "defined"), .{ .object = def_obj });
        return .{ .object = obj };
    }

    // String type
    if (info == .pointer and info.pointer.size == .Slice and info.pointer.child == u8) {
        return jsonString(a, "string");
    }

    // Fallback
    return jsonString(a, "bytes");
}

fn registerType(
    a: Allocator,
    comptime T: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !void {
    const type_name = @typeName(T);
    const short_name = shortTypeName(type_name);

    if (type_registry.contains(short_name)) return;
    try type_registry.put(try a.dupe(u8, short_name), {});

    const info = @typeInfo(T);

    if (info == .@"struct") {
        var obj = std.json.ObjectMap.init(a);
        try putString(a, &obj, "name", short_name);

        var type_obj = std.json.ObjectMap.init(a);
        try putString(a, &type_obj, "kind", "struct");
        try type_obj.put(try a.dupe(u8, "fields"), try buildTypeFields(a, T, type_registry, type_defs));
        try obj.put(try a.dupe(u8, "type"), .{ .object = type_obj });

        try type_defs.append(.{ .object = obj });
    } else if (info == .@"enum") {
        var obj = std.json.ObjectMap.init(a);
        try putString(a, &obj, "name", short_name);

        var type_obj = std.json.ObjectMap.init(a);
        try putString(a, &type_obj, "kind", "enum");

        var variants = std.json.Array.init(a);
        inline for (info.@"enum".fields) |field| {
            var var_obj = std.json.ObjectMap.init(a);
            try putString(a, &var_obj, "name", field.name);
            try variants.append(.{ .object = var_obj });
        }
        try type_obj.put(try a.dupe(u8, "variants"), .{ .array = variants });
        try obj.put(try a.dupe(u8, "type"), .{ .object = type_obj });
        try type_defs.append(.{ .object = obj });
    } else if (info == .@"union") {
        // Tagged union (Rust enum with data)
        var obj = std.json.ObjectMap.init(a);
        try putString(a, &obj, "name", short_name);

        var type_obj = std.json.ObjectMap.init(a);
        try putString(a, &type_obj, "kind", "enum");

        var variants = std.json.Array.init(a);
        inline for (info.@"union".fields) |field| {
            var var_obj = std.json.ObjectMap.init(a);
            try putString(a, &var_obj, "name", field.name);

            // Add field type if not void
            if (field.type != void) {
                var fields_arr = std.json.Array.init(a);
                var field_obj = std.json.ObjectMap.init(a);
                try putString(a, &field_obj, "name", "data");
                try field_obj.put(try a.dupe(u8, "type"), try typeToJson(a, field.type, type_registry, type_defs));
                try fields_arr.append(.{ .object = field_obj });
                try var_obj.put(try a.dupe(u8, "fields"), .{ .array = fields_arr });
            }

            try variants.append(.{ .object = var_obj });
        }
        try type_obj.put(try a.dupe(u8, "variants"), .{ .array = variants });
        try obj.put(try a.dupe(u8, "type"), .{ .object = type_obj });

        try type_defs.append(.{ .object = obj });
    }
}

fn buildTypeFields(
    a: Allocator,
    comptime T: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    var arr = std.json.Array.init(a);

    const fields = std.meta.fields(T);
    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(a);
        try putString(a, &obj, "name", field.name);
        try obj.put(try a.dupe(u8, "type"), try typeToJson(a, field.type, type_registry, type_defs));
        try arr.append(.{ .object = obj });
    }

    return .{ .array = arr };
}

// ============================================================================
// Helpers
// ============================================================================

fn putString(a: Allocator, obj: *std.json.ObjectMap, key: []const u8, value: anytype) !void {
    const T = @TypeOf(value);
    if (T == @TypeOf(null)) {
        // Skip null values
        return;
    }
    if (T == []const u8) {
        try obj.put(try a.dupe(u8, key), jsonString(a, value));
    } else if (@typeInfo(T) == .@"struct" and @hasField(T, "name")) {
        try obj.put(try a.dupe(u8, key), jsonString(a, value.name));
    } else {
        try obj.put(try a.dupe(u8, key), jsonString(a, value));
    }
}

fn jsonString(a: Allocator, s: []const u8) std.json.Value {
    return .{ .string = a.dupe(u8, s) catch s };
}

fn discriminatorJson(a: Allocator, disc: [8]u8) !std.json.Value {
    var arr = std.json.Array.init(a);
    try arr.ensureTotalCapacity(8);
    for (disc) |b| {
        arr.appendAssumeCapacity(.{ .integer = b });
    }
    return .{ .array = arr };
}

fn shortTypeName(full_name: []const u8) []const u8 {
    // Extract last component after '.'
    var i = full_name.len;
    while (i > 0) : (i -= 1) {
        if (full_name[i - 1] == '.') {
            return full_name[i..];
        }
    }
    return full_name;
}

// ============================================================================
// Tests
// ============================================================================

test "instruction definition" {
    const TestAccounts = struct {
        authority: zero_cu.Signer(0),
    };
    const TestInstr = Instruction("test", TestAccounts, void);

    try std.testing.expectEqualStrings("test", TestInstr.instruction_name);
    try std.testing.expect(TestInstr.ArgsType == void);
}

test "account definition" {
    const TestData = struct { value: u64 };
    const TestAcc = AccountDef("Test", TestData);

    try std.testing.expectEqualStrings("Test", TestAcc.account_name);
    try std.testing.expect(TestAcc.DataType == TestData);
}
