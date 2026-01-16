//! Zig implementation of Anchor IDL generation
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/idl.rs
//!
//! This module generates Anchor-compatible IDL JSON from comptime program
//! definitions. It focuses on instructions, accounts, args, and errors.

const std = @import("std");
const discriminator_mod = @import("discriminator.zig");
const signer_mod = @import("signer.zig");
const program_mod = @import("program.zig");
const seeds_mod = @import("seeds.zig");
const has_one_mod = @import("has_one.zig");
const realloc_mod = @import("realloc.zig");
const constraints_mod = @import("constraints.zig");
const sol = @import("solana_program_sdk");

const Allocator = std.mem.Allocator;

const Signer = signer_mod.Signer;
const SignerMut = signer_mod.SignerMut;
const UncheckedProgram = program_mod.UncheckedProgram;
const SeedSpec = seeds_mod.SeedSpec;
const HasOneSpec = has_one_mod.HasOneSpec;
const ReallocConfig = realloc_mod.ReallocConfig;
const ConstraintExpr = constraints_mod.ConstraintExpr;
const PublicKey = sol.PublicKey;

pub const IdlConfig = struct {
    /// Force mutable account names
    mut: ?[]const []const u8 = null,
    /// Force signer account names
    signer: ?[]const []const u8 = null,
};

pub const InstructionSpec = struct {
    Accounts: type,
    Args: type = void,
};

/// Instruction descriptor for comptime programs
pub fn Instruction(comptime spec: InstructionSpec) type {
    return struct {
        pub const Accounts = spec.Accounts;
        pub const Args = spec.Args;
    };
}

pub const AccountDescriptor = struct {
    name: []const u8,
    is_mut: bool,
    is_signer: bool,
    is_program: bool,
    is_optional: bool,
    program_id: ?PublicKey = null,
    constraints: ?ConstraintDescriptor = null,
};

pub const ConstraintDescriptor = struct {
    seeds: ?[]const SeedSpec = null,
    bump: bool = false,
    seeds_program: ?SeedSpec = null,
    init: bool = false,
    payer: ?[]const u8 = null,
    close: ?[]const u8 = null,
    realloc: ?ReallocConfig = null,
    has_one: ?[]const HasOneSpec = null,
    rent_exempt: bool = false,
    constraint: ?ConstraintExpr = null,
    owner: ?PublicKey = null,
    address: ?PublicKey = null,
    executable: bool = false,
};

/// Generate Anchor-compatible IDL JSON.
pub fn generateJson(allocator: Allocator, comptime program: anytype, comptime config: IdlConfig) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var type_registry = std.StringHashMap(void).init(a);
    var type_defs = std.json.Array.init(a);
    var account_registry = std.StringHashMap(void).init(a);
    var account_defs = std.json.Array.init(a);

    const name = programTypeName(program);
    var address_buffer: [44]u8 = undefined;
    const address = program.id.toBase58(&address_buffer);

    const instructions = try buildInstructionsJson(a, program, config, &type_registry, &type_defs, &account_registry, &account_defs);
    const errors = try buildErrorsJson(a, program);
    const constants = try buildConstantsJson(a, program, &type_registry, &type_defs);
    const events = try buildEventsJson(a, program, &type_registry, &type_defs);
    const metadata = try buildMetadataJson(a, program, name);

    var root = std.json.ObjectMap.init(a);
    try putString(a, &root, "address", address);
    try root.put(try a.dupe(u8, "metadata"), metadata);
    try root.put(try a.dupe(u8, "instructions"), instructions);
    try root.put(try a.dupe(u8, "accounts"), .{ .array = account_defs });
    try root.put(try a.dupe(u8, "types"), .{ .array = type_defs });
    try root.put(try a.dupe(u8, "errors"), errors);
    if (constants != null) {
        try root.put(try a.dupe(u8, "constants"), constants.?);
    }
    if (events != null) {
        try root.put(try a.dupe(u8, "events"), events.?);
    }

    const json = std.json.Value{ .object = root };
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var write_stream: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .whitespace = .indent_2 },
    };
    try write_stream.write(json);
    return try out.toOwnedSlice();
}

/// Write Anchor IDL JSON to a file path.
pub fn writeJsonFile(
    allocator: Allocator,
    comptime program: anytype,
    comptime config: IdlConfig,
    output_path: []const u8,
) !void {
    const json = try generateJson(allocator, program, config);
    defer allocator.free(json);

    const dir = std.fs.path.dirname(output_path) orelse ".";
    try std.fs.cwd().makePath(dir);

    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(json);
}

fn buildInstructionsJson(
    allocator: Allocator,
    comptime program: anytype,
    comptime config: IdlConfig,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
    account_registry: *std.StringHashMap(void),
    account_defs: *std.json.Array,
) !std.json.Value {
    const decls = comptime @typeInfo(program.instructions).@"struct".decls;
    var instructions = std.json.Array.init(allocator);
    try instructions.ensureTotalCapacity(decls.len);

    inline for (decls) |decl| {
        const InstructionType = @field(program.instructions, decl.name);
        if (@TypeOf(InstructionType) != type) continue;
        if (!@hasDecl(InstructionType, "Accounts")) {
            @compileError("Instruction type must define Accounts");
        }
        if (!@hasDecl(InstructionType, "Args")) {
            @compileError("Instruction type must define Args");
        }

        const Accounts = InstructionType.Accounts;
        const Args = InstructionType.Args;
        const accounts = extractAccounts(Accounts, config);

        var ix_obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &ix_obj, "name", decl.name);
        const discriminator = comptime discriminator_mod.instructionDiscriminator(decl.name);
        try ix_obj.put(try allocator.dupe(u8, "discriminator"), try discriminatorArrayJson(allocator, discriminator));
        try ix_obj.put(try allocator.dupe(u8, "accounts"), try accountsJson(allocator, accounts));
        try ix_obj.put(try allocator.dupe(u8, "args"), try argsJson(allocator, Args, type_registry, type_defs));

        try appendAccountDefsForAccounts(allocator, Accounts, account_registry, account_defs, type_registry, type_defs);

        instructions.appendAssumeCapacity(.{ .object = ix_obj });
    }

    return .{ .array = instructions };
}

fn buildErrorsJson(allocator: Allocator, comptime program: anytype) !std.json.Value {
    if (!@hasDecl(program, "errors")) {
        return .{ .array = std.json.Array.init(allocator) };
    }

    const Errors = @TypeOf(program.errors);
    const info = @typeInfo(Errors);
    if (info != .@"enum") {
        return .{ .array = std.json.Array.init(allocator) };
    }

    const fields = info.@"enum".fields;
    var errors = std.json.Array.init(allocator);
    try errors.ensureTotalCapacity(fields.len);

    inline for (fields) |field| {
        const code = @intFromEnum(@field(Errors, field.name));
        var err_obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &err_obj, "name", field.name);
        try err_obj.put(try allocator.dupe(u8, "code"), .{ .integer = @intCast(code) });
        errors.appendAssumeCapacity(.{ .object = err_obj });
    }

    return .{ .array = errors };
}

fn buildConstantsJson(
    allocator: Allocator,
    comptime program: anytype,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !?std.json.Value {
    if (!@hasDecl(program, "constants")) {
        return null;
    }

    const constants = program.constants;
    const info = @typeInfo(@TypeOf(constants));
    if (info != .@"struct") {
        @compileError("Program constants must be a struct literal");
    }

    const fields = info.@"struct".fields;
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(fields.len);

    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        const type_value = try typeToJson(allocator, field.type, type_registry, type_defs);
        const value = @field(constants, field.name);
        const value_string = try valueToString(allocator, field.type, value);
        const value_json = jsonString(allocator, value_string);
        try obj.put(try allocator.dupe(u8, "type"), type_value);
        try obj.put(try allocator.dupe(u8, "value"), value_json);
        arr.appendAssumeCapacity(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn buildEventsJson(
    allocator: Allocator,
    comptime program: anytype,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !?std.json.Value {
    if (!@hasDecl(program, "events")) {
        return null;
    }

    const events = program.events;
    const info = if (@TypeOf(events) == type) @typeInfo(events) else @typeInfo(@TypeOf(events));
    if (info != .@"struct") {
        @compileError("Program events must be a struct");
    }

    const fields = comptime info.@"struct".decls;
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(fields.len);

    inline for (fields) |field| {
        const EventType = @field(events, field.name);
        if (@TypeOf(EventType) != type or @typeInfo(EventType) != .@"struct") {
            @compileError("Event types must be structs");
        }

        var obj = std.json.ObjectMap.init(allocator);
        const event_name = field.name;
        try putString(allocator, &obj, "name", event_name);
        const event_discriminator = comptime discriminator_mod.eventDiscriminator(event_name);
        try obj.put(try allocator.dupe(u8, "discriminator"), try discriminatorArrayJson(allocator, event_discriminator));
        try ensureTypeDef(allocator, EventType, event_name, type_registry, type_defs);
        arr.appendAssumeCapacity(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn buildMetadataJson(
    allocator: Allocator,
    comptime program: anytype,
    program_name: []const u8,
) !std.json.Value {
    var obj = std.json.ObjectMap.init(allocator);
    const default_version = "0.1.0";
    const default_spec = "0.1.0";

    if (@hasDecl(program, "metadata")) {
        const metadata = program.metadata;
        const info = @typeInfo(@TypeOf(metadata));
        if (info != .@"struct") {
            @compileError("Program metadata must be a struct literal");
        }

        const has_name = try putMetadataField(allocator, &obj, metadata, "name");
        if (!has_name) {
            try putString(allocator, &obj, "name", program_name);
        }
        const has_version = try putMetadataField(allocator, &obj, metadata, "version");
        if (!has_version) {
            try putString(allocator, &obj, "version", default_version);
        }
        const has_spec = try putMetadataField(allocator, &obj, metadata, "spec");
        if (!has_spec) {
            try putString(allocator, &obj, "spec", default_spec);
        }

        _ = try putMetadataField(allocator, &obj, metadata, "description");
        _ = try putMetadataField(allocator, &obj, metadata, "repository");
        _ = try putMetadataField(allocator, &obj, metadata, "dependencies");
        _ = try putMetadataField(allocator, &obj, metadata, "contact");
        _ = try putMetadataField(allocator, &obj, metadata, "deployments");

        return .{ .object = obj };
    }

    try putString(allocator, &obj, "name", program_name);
    try putString(allocator, &obj, "version", default_version);
    try putString(allocator, &obj, "spec", default_spec);
    return .{ .object = obj };
}

fn putMetadataField(
    allocator: Allocator,
    obj: *std.json.ObjectMap,
    metadata: anytype,
    comptime field_name: []const u8,
) !bool {
    if (!@hasField(@TypeOf(metadata), field_name)) {
        return false;
    }
    const value = @field(metadata, field_name);
    if (@typeInfo(@TypeOf(value)) == .optional and value == null) {
        return false;
    }
    const value_json = try valueToJson(allocator, @TypeOf(value), value);
    try obj.put(try allocator.dupe(u8, field_name), value_json);
    return true;
}

fn accountsJson(allocator: Allocator, accounts: []const AccountDescriptor) !std.json.Value {
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(accounts.len);

    for (accounts) |account| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", account.name);
        if (account.is_mut) {
            try obj.put(try allocator.dupe(u8, "writable"), .{ .bool = true });
        }
        if (account.is_signer) {
            try obj.put(try allocator.dupe(u8, "signer"), .{ .bool = true });
        }
        if (account.is_optional) {
            try obj.put(try allocator.dupe(u8, "optional"), .{ .bool = true });
        }

        if (account.constraints) |constraints| {
            if (constraints.address) |address| {
                var buffer: [44]u8 = undefined;
                try obj.put(try allocator.dupe(u8, "address"), jsonString(allocator, address.toBase58(&buffer)));
            } else if (account.program_id) |program_id| {
                var buffer: [44]u8 = undefined;
                try obj.put(try allocator.dupe(u8, "address"), jsonString(allocator, program_id.toBase58(&buffer)));
            }
            if (constraints.seeds) |seeds| {
                var pda_obj = std.json.ObjectMap.init(allocator);
                try pda_obj.put(try allocator.dupe(u8, "seeds"), try seedsJson(allocator, seeds));
                if (constraints.seeds_program) |program| {
                    try pda_obj.put(try allocator.dupe(u8, "program"), try seedJson(allocator, program));
                }
                try obj.put(try allocator.dupe(u8, "pda"), .{ .object = pda_obj });
            }
            if (constraints.has_one) |has_one| {
                var relations = std.json.Array.init(allocator);
                try relations.ensureTotalCapacity(has_one.len);
                for (has_one) |spec| {
                    relations.appendAssumeCapacity(jsonString(allocator, spec.target));
                }
                if (relations.items.len > 0) {
                    try obj.put(try allocator.dupe(u8, "relations"), .{ .array = relations });
                }
            }
        } else if (account.program_id) |program_id| {
            var buffer: [44]u8 = undefined;
            try obj.put(try allocator.dupe(u8, "address"), jsonString(allocator, program_id.toBase58(&buffer)));
        }
        arr.appendAssumeCapacity(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn argsJson(
    allocator: Allocator,
    comptime Args: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    if (Args == void) {
        return .{ .array = std.json.Array.init(allocator) };
    }

    const info = @typeInfo(Args);
    if (info != .@"struct") {
        @compileError("Instruction Args must be a struct or void");
    }

    const fields = info.@"struct".fields;
    var args = std.json.Array.init(allocator);
    try args.ensureTotalCapacity(fields.len);

    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        const type_value = try typeToJson(allocator, field.type, type_registry, type_defs);
        try obj.put(try allocator.dupe(u8, "type"), type_value);
        args.appendAssumeCapacity(.{ .object = obj });
    }

    return .{ .array = args };
}

fn discriminatorJson(allocator: Allocator, comptime name: []const u8) !std.json.Value {
    const discriminator = discriminator_mod.instructionDiscriminator(name);
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(discriminator.len);
    for (discriminator) |byte| {
        arr.appendAssumeCapacity(.{ .integer = byte });
    }
    return .{ .array = arr };
}

fn eventDiscriminatorJson(allocator: Allocator, comptime name: []const u8) !std.json.Value {
    const discriminator = discriminator_mod.eventDiscriminator(name);
    return discriminatorArrayJson(allocator, discriminator);
}

fn eventFieldsJson(
    allocator: Allocator,
    comptime EventType: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    const fields = @typeInfo(EventType).@"struct".fields;
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(fields.len);

    inline for (fields) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        const field_type = @import("typed_dsl.zig").unwrapEventField(field.type);
        const field_config = @import("typed_dsl.zig").eventFieldConfig(field.type);
        const type_value = try typeToJson(allocator, field_type, type_registry, type_defs);
        try obj.put(try allocator.dupe(u8, "type"), type_value);
        try obj.put(try allocator.dupe(u8, "index"), .{ .bool = field_config.index });
        arr.appendAssumeCapacity(.{ .object = obj });
    }

    return .{ .array = arr };
}

fn constraintsJson(allocator: Allocator, constraints: ConstraintDescriptor) !?std.json.Value {
    var obj = std.json.ObjectMap.init(allocator);
    var has_entries = false;

    if (constraints.seeds) |seeds| {
        try obj.put(try allocator.dupe(u8, "seeds"), try seedsJson(allocator, seeds));
        has_entries = true;
    }
    if (constraints.bump) {
        try obj.put(try allocator.dupe(u8, "bump"), .{ .bool = true });
        has_entries = true;
    }
    if (constraints.init) {
        try obj.put(try allocator.dupe(u8, "init"), .{ .bool = true });
        has_entries = true;
    }
    if (constraints.payer) |payer| {
        try obj.put(try allocator.dupe(u8, "payer"), jsonString(allocator, payer));
        has_entries = true;
    }
    if (constraints.close) |close| {
        try obj.put(try allocator.dupe(u8, "close"), jsonString(allocator, close));
        has_entries = true;
    }
    if (constraints.realloc) |realloc| {
        var realloc_obj = std.json.ObjectMap.init(allocator);
        if (realloc.payer) |payer| {
            try realloc_obj.put(try allocator.dupe(u8, "payer"), jsonString(allocator, payer));
        }
        try realloc_obj.put(try allocator.dupe(u8, "zeroInit"), .{ .bool = realloc.zero_init });
        try obj.put(try allocator.dupe(u8, "realloc"), .{ .object = realloc_obj });
        has_entries = true;
    }
    if (constraints.has_one) |has_one| {
        var relations = std.json.Array.init(allocator);
        try relations.ensureTotalCapacity(has_one.len);
        for (has_one) |spec| {
            relations.appendAssumeCapacity(jsonString(allocator, spec.target));
        }
        try obj.put(try allocator.dupe(u8, "hasOne"), .{ .array = relations });
        has_entries = true;
    }
    if (constraints.rent_exempt) {
        try obj.put(try allocator.dupe(u8, "rentExempt"), .{ .bool = true });
        has_entries = true;
    }
    if (constraints.constraint) |expr| {
        try obj.put(try allocator.dupe(u8, "constraint"), jsonString(allocator, expr.expr));
        has_entries = true;
    }
    if (constraints.owner) |owner| {
        var buf: [44]u8 = undefined;
        try obj.put(try allocator.dupe(u8, "owner"), jsonString(allocator, owner.toBase58(&buf)));
        has_entries = true;
    }
    if (constraints.address) |address| {
        var buf: [44]u8 = undefined;
        try obj.put(try allocator.dupe(u8, "address"), jsonString(allocator, address.toBase58(&buf)));
        has_entries = true;
    }
    if (constraints.executable) {
        try obj.put(try allocator.dupe(u8, "executable"), .{ .bool = true });
        has_entries = true;
    }

    if (!has_entries) {
        return null;
    }

    return .{ .object = obj };
}

fn seedJson(allocator: Allocator, spec: SeedSpec) !std.json.Value {
    var obj = std.json.ObjectMap.init(allocator);
    switch (spec) {
        .literal => |value| {
            try putString(allocator, &obj, "kind", "const");
            try obj.put(try allocator.dupe(u8, "value"), try bytesArrayJson(allocator, value));
        },
        .account => |value| {
            try putString(allocator, &obj, "kind", "account");
            try obj.put(try allocator.dupe(u8, "path"), jsonString(allocator, value));
        },
        .field => |value| {
            try putString(allocator, &obj, "kind", "arg");
            try obj.put(try allocator.dupe(u8, "path"), jsonString(allocator, value));
        },
        .bump => |value| {
            try putString(allocator, &obj, "kind", "arg");
            try obj.put(try allocator.dupe(u8, "path"), jsonString(allocator, value));
        },
    }
    return .{ .object = obj };
}

fn seedsJson(allocator: Allocator, seeds: []const SeedSpec) !std.json.Value {
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(seeds.len);

    for (seeds) |spec| {
        arr.appendAssumeCapacity(try seedJson(allocator, spec));
    }

    return .{ .array = arr };
}

fn valueToJson(allocator: Allocator, comptime T: type, value: T) !std.json.Value {
    const info = @typeInfo(T);

    if (info == .optional) {
        if (value == null) {
            return .{ .null = {} };
        }
        return valueToJson(allocator, info.optional.child, value.?);
    }

    if (comptime isPublicKeyType(T)) {
        var buffer: [44]u8 = undefined;
        const encoded = value.toBase58(&buffer);
        return jsonString(allocator, encoded);
    }

    switch (info) {
        .bool => return .{ .bool = value },
        .int => return .{ .integer = @intCast(value) },
        .float => return .{ .float = @floatCast(value) },
        .pointer => |ptr| {
            const child_info = @typeInfo(ptr.child);
            if (ptr.size != .slice) {
                if (child_info == .array and child_info.array.child == u8) {
                    return jsonString(allocator, value.*[0..]);
                }
                @compileError("IDL only supports slices for pointer types");
            }
            if (ptr.child == u8) {
                return jsonString(allocator, value);
            }
        },
        else => {},
    }

    @compileError("Unsupported constant type for IDL: " ++ @typeName(T));
}

fn valueToString(allocator: Allocator, comptime T: type, value: T) ![]u8 {
    const info = @typeInfo(T);

    if (info == .optional) {
        if (value == null) {
            return allocator.dupe(u8, "None");
        }
        const inner = try valueToString(allocator, info.optional.child, value.?);
        defer allocator.free(inner);
        return std.fmt.allocPrint(allocator, "Some({s})", .{inner});
    }

    if (comptime isPublicKeyType(T)) {
        var buffer: [44]u8 = undefined;
        return allocator.dupe(u8, value.toBase58(&buffer));
    }

    switch (info) {
        .bool => return allocator.dupe(u8, if (value) "true" else "false"),
        .int => return std.fmt.allocPrint(allocator, "{d}", .{value}),
        .float => return std.fmt.allocPrint(allocator, "{d}", .{value}),
        .array => return formatArrayString(allocator, T, value),
        .pointer => |ptr| {
            const child_info = @typeInfo(ptr.child);
            if (ptr.size != .slice) {
                if (child_info == .array and child_info.array.child == u8) {
                    return std.fmt.allocPrint(allocator, "\"{s}\"", .{value.*[0..]});
                }
                @compileError("IDL only supports slices for pointer types");
            }
            if (ptr.child == u8) {
                return formatSliceString(allocator, u8, value);
            }
            return formatSliceString(allocator, ptr.child, value);
        },
        else => {},
    }

    @compileError("Unsupported constant type for IDL: " ++ @typeName(T));
}

fn formatArrayString(allocator: Allocator, comptime T: type, value: T) ![]u8 {
    const len = @typeInfo(T).array.len;
    var out = try std.ArrayList(u8).initCapacity(allocator, len * 4 + 2);
    errdefer out.deinit(allocator);

    try out.append(allocator, '[');
    inline for (value, 0..) |item, index| {
        if (index != 0) {
            try out.appendSlice(allocator, ", ");
        }
        const item_string = try valueToString(allocator, @TypeOf(item), item);
        defer allocator.free(item_string);
        try out.appendSlice(allocator, item_string);
    }
    try out.append(allocator, ']');

    return try out.toOwnedSlice(allocator);
}

fn formatSliceString(allocator: Allocator, comptime T: type, slice: []const T) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, slice.len * 4 + 2);
    errdefer out.deinit(allocator);

    try out.append(allocator, '[');
    for (slice, 0..) |item, index| {
        if (index != 0) {
            try out.appendSlice(allocator, ", ");
        }
        const item_string = try valueToString(allocator, T, item);
        defer allocator.free(item_string);
        try out.appendSlice(allocator, item_string);
    }
    try out.append(allocator, ']');

    return try out.toOwnedSlice(allocator);
}

fn appendAccountDefsForAccounts(
    allocator: Allocator,
    comptime Accounts: type,
    account_registry: *std.StringHashMap(void),
    account_defs: *std.json.Array,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !void {
    const fields = comptime @typeInfo(Accounts).@"struct".fields;

    inline for (fields) |field| {
        const FieldType = field.type;
        if (comptime !isAccountWrapper(FieldType)) continue;

        const data_type = FieldType.DataType;
        const name = accountTypeName(FieldType, data_type);
        if (!account_registry.contains(name)) {
            try account_registry.put(try allocator.dupe(u8, name), {});

            var account_obj = std.json.ObjectMap.init(allocator);
            try putString(allocator, &account_obj, "name", name);
            try account_obj.put(try allocator.dupe(u8, "discriminator"), try discriminatorArrayJson(allocator, FieldType.discriminator));
            try ensureTypeDef(allocator, data_type, name, type_registry, type_defs);

            try account_defs.append(.{ .object = account_obj });
        }
    }
}

fn typeToJson(
    allocator: Allocator,
    comptime T: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    const info = @typeInfo(T);

    if (comptime isPublicKeyType(T)) {
        return jsonString(allocator, "pubkey");
    }

    switch (info) {
        .bool => return jsonString(allocator, "bool"),
        .int => |int_info| {
            if (int_info.bits != 8 and int_info.bits != 16 and int_info.bits != 32 and int_info.bits != 64 and int_info.bits != 128 and int_info.bits != 256) {
                @compileError("Unsupported integer size for IDL: " ++ @typeName(T));
            }
            const tag = if (int_info.signedness == .signed) "i" else "u";
            const type_name = try std.fmt.allocPrint(allocator, "{s}{d}", .{ tag, int_info.bits });
            return jsonString(allocator, type_name);
        },
        .float => |float_info| {
            const type_name = try std.fmt.allocPrint(allocator, "f{d}", .{float_info.bits});
            return jsonString(allocator, type_name);
        },
        .optional => |opt| {
            const child = try typeToJson(allocator, opt.child, type_registry, type_defs);
            var obj = std.json.ObjectMap.init(allocator);
            try obj.put(try allocator.dupe(u8, "option"), child);
            return .{ .object = obj };
        },
        .array => |arr| {
            const child = try typeToJson(allocator, arr.child, type_registry, type_defs);
            var list = std.json.Array.init(allocator);
            try list.ensureTotalCapacity(2);
            list.appendAssumeCapacity(child);
            list.appendAssumeCapacity(.{ .integer = @intCast(arr.len) });
            var obj = std.json.ObjectMap.init(allocator);
            try obj.put(try allocator.dupe(u8, "array"), .{ .array = list });
            return .{ .object = obj };
        },
        .pointer => |ptr| {
            const child_info = @typeInfo(ptr.child);
            if (ptr.size != .slice) {
                if (child_info == .array and child_info.array.child == u8) {
                    return jsonString(allocator, "string");
                }
                @compileError("IDL only supports slices for pointer types");
            }
            if (ptr.child == u8) {
                return jsonString(allocator, "bytes");
            }
            const child = try typeToJson(allocator, ptr.child, type_registry, type_defs);
            var obj = std.json.ObjectMap.init(allocator);
            try obj.put(try allocator.dupe(u8, "vec"), child);
            return .{ .object = obj };
        },
        .@"struct" => {
            const name = shortTypeName(@typeName(T));
            try ensureTypeDef(allocator, T, name, type_registry, type_defs);
            return definedTypeJson(allocator, name);
        },
        .@"enum" => {
            const name = shortTypeName(@typeName(T));
            try ensureEnumTypeDef(allocator, T, name, type_registry, type_defs);
            return definedTypeJson(allocator, name);
        },
        else => @compileError("Unsupported IDL type: " ++ @typeName(T)),
    }
}

fn ensureTypeDef(
    allocator: Allocator,
    comptime T: type,
    name: []const u8,
    registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !void {
    if (registry.contains(name)) return;
    try registry.put(try allocator.dupe(u8, name), {});

    const info = @typeInfo(T).@"struct".fields;
    var fields = std.json.Array.init(allocator);
    try fields.ensureTotalCapacity(info.len);

    inline for (info) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        const FieldType = if (@typeInfo(field.type) == .@"struct")
            @import("typed_dsl.zig").unwrapEventField(field.type)
        else
            field.type;
        const value = try typeToJson(allocator, FieldType, registry, type_defs);
        try obj.put(try allocator.dupe(u8, "type"), value);
        fields.appendAssumeCapacity(.{ .object = obj });
    }

    var type_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &type_obj, "kind", "struct");
    try type_obj.put(try allocator.dupe(u8, "fields"), .{ .array = fields });

    var def_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &def_obj, "name", name);
    try def_obj.put(try allocator.dupe(u8, "type"), .{ .object = type_obj });

    try type_defs.append(.{ .object = def_obj });
}

fn ensureEnumTypeDef(
    allocator: Allocator,
    comptime T: type,
    name: []const u8,
    registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !void {
    if (registry.contains(name)) return;
    try registry.put(try allocator.dupe(u8, name), {});

    const info = @typeInfo(T).@"enum".fields;
    var variants = std.json.Array.init(allocator);
    try variants.ensureTotalCapacity(info.len);

    inline for (info) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        variants.appendAssumeCapacity(.{ .object = obj });
    }

    var type_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &type_obj, "kind", "enum");
    try type_obj.put(try allocator.dupe(u8, "variants"), .{ .array = variants });

    var def_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &def_obj, "name", name);
    try def_obj.put(try allocator.dupe(u8, "type"), .{ .object = type_obj });

    try type_defs.append(.{ .object = def_obj });
}

fn jsonString(allocator: Allocator, value: []const u8) std.json.Value {
    _ = allocator;
    return .{ .string = value };
}

fn putString(allocator: Allocator, obj: *std.json.ObjectMap, key: []const u8, value: []const u8) !void {
    try obj.put(try allocator.dupe(u8, key), jsonString(allocator, value));
}

fn discriminatorArrayJson(allocator: Allocator, discriminator: [8]u8) !std.json.Value {
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(discriminator.len);
    for (discriminator) |byte| {
        arr.appendAssumeCapacity(.{ .integer = byte });
    }
    return .{ .array = arr };
}

fn bytesArrayJson(allocator: Allocator, bytes: []const u8) !std.json.Value {
    var arr = std.json.Array.init(allocator);
    try arr.ensureTotalCapacity(bytes.len);
    for (bytes) |byte| {
        arr.appendAssumeCapacity(.{ .integer = byte });
    }
    return .{ .array = arr };
}

fn structTypeJson(
    allocator: Allocator,
    comptime T: type,
    type_registry: *std.StringHashMap(void),
    type_defs: *std.json.Array,
) !std.json.Value {
    const info = @typeInfo(T).@"struct".fields;
    var fields = std.json.Array.init(allocator);
    try fields.ensureTotalCapacity(info.len);

    inline for (info) |field| {
        var obj = std.json.ObjectMap.init(allocator);
        try putString(allocator, &obj, "name", field.name);
        const FieldType = if (@typeInfo(field.type) == .@"struct")
            @import("typed_dsl.zig").unwrapEventField(field.type)
        else
            field.type;
        const value = try typeToJson(allocator, FieldType, type_registry, type_defs);
        try obj.put(try allocator.dupe(u8, "type"), value);
        fields.appendAssumeCapacity(.{ .object = obj });
    }

    var type_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &type_obj, "kind", "struct");
    try type_obj.put(try allocator.dupe(u8, "fields"), .{ .array = fields });

    return .{ .object = type_obj };
}

fn accountTypeName(comptime AccountType: type, comptime DataType: type) []const u8 {
    const full_name = @typeName(AccountType);
    if (std.mem.indexOf(u8, full_name, "Account(") != null or std.mem.eql(u8, full_name, "Account")) {
        return shortTypeName(@typeName(DataType));
    }
    return shortTypeName(full_name);
}

fn isPublicKeyType(comptime T: type) bool {
    return std.mem.endsWith(u8, @typeName(T), "PublicKey");
}

fn isSignerType(comptime T: type) bool {
    return T == Signer;
}

fn isSignerMutType(comptime T: type) bool {
    return T == SignerMut;
}

fn isProgramType(comptime T: type) bool {
    @setEvalBranchQuota(10000);
    return T == UncheckedProgram or std.mem.indexOf(u8, @typeName(T), "Program(") != null;
}

fn isAccountWrapper(comptime T: type) bool {
    return @hasDecl(T, "DataType") and @hasDecl(T, "discriminator");
}

fn accountConstraints(comptime T: type) ?ConstraintDescriptor {
    if (comptime !isAccountWrapper(T)) return null;

    const constraints = ConstraintDescriptor{
        .seeds = T.SEEDS,
        .bump = T.HAS_BUMP,
        .seeds_program = T.SEEDS_PROGRAM,
        .init = T.IS_INIT,
        .payer = T.PAYER,
        .close = T.CLOSE,
        .realloc = T.REALLOC,
        .has_one = T.HAS_ONE,
        .rent_exempt = T.RENT_EXEMPT,
        .constraint = T.CONSTRAINT,
        .owner = T.OWNER,
        .address = T.ADDRESS,
        .executable = T.EXECUTABLE,
    };

    if (constraints.seeds == null and !constraints.bump and !constraints.init and constraints.payer == null and constraints.close == null and constraints.realloc == null and constraints.has_one == null and !constraints.rent_exempt and constraints.constraint == null and constraints.owner == null and constraints.address == null and !constraints.executable) {
        return null;
    }

    return constraints;
}

pub fn extractAccounts(comptime Accounts: type, comptime config: IdlConfig) []const AccountDescriptor {
    const result = comptime buildAccountDescriptors(Accounts, config);
    return result[0..];
}

fn buildAccountDescriptors(
    comptime Accounts: type,
    comptime config: IdlConfig,
) [@typeInfo(Accounts).@"struct".fields.len]AccountDescriptor {
    const fields = @typeInfo(Accounts).@"struct".fields;
    comptime var result: [fields.len]AccountDescriptor = undefined;

    inline for (fields, 0..) |field, index| {
        const RawType = field.type;
        const FieldType = baseAccountType(RawType);
        const is_optional = comptime isOptionalType(RawType);

        comptime var is_signer = isSignerType(FieldType) or isSignerMutType(FieldType);
        comptime var is_mut = isSignerMutType(FieldType);
        comptime var program_id: ?PublicKey = null;

        if (comptime isAccountWrapper(FieldType)) {
            if (FieldType.HAS_MUT) {
                is_mut = true;
            }
            if (FieldType.HAS_SIGNER) {
                is_signer = true;
            }
        }
        if (comptime isProgramType(FieldType) and @hasDecl(FieldType, "ID")) {
            program_id = FieldType.ID;
        }

        if (comptime nameInList(config.signer, field.name)) {
            is_signer = true;
        }
        if (comptime nameInList(config.mut, field.name)) {
            is_mut = true;
        }

        const is_program = comptime isProgramType(FieldType);
        const constraints = comptime accountConstraints(FieldType);

        result[index] = .{
            .name = field.name,
            .is_mut = is_mut,
            .is_signer = is_signer,
            .is_program = is_program,
            .is_optional = is_optional,
            .program_id = program_id,
            .constraints = constraints,
        };
    }

    return result;
}

fn isOptionalType(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn baseAccountType(comptime T: type) type {
    return if (@typeInfo(T) == .optional) @typeInfo(T).optional.child else T;
}

fn nameInList(comptime list: ?[]const []const u8, comptime name: []const u8) bool {
    if (list == null) return false;
    inline for (list.?) |item| {
        if (std.mem.eql(u8, item, name)) return true;
    }
    return false;
}

pub fn shortTypeName(full: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, full, '.')) |index| {
        return full[index + 1 ..];
    }
    return full;
}

/// Returns the default IDL name for a program.
pub fn defaultIdlName(comptime program: anytype) []const u8 {
    if (@TypeOf(program) == type and @hasDecl(program, "metadata")) {
        const metadata = program.metadata;
        if (@hasField(@TypeOf(metadata), "name")) {
            return metadata.name;
        }
    }
    return programTypeName(program);
}

fn programTypeName(comptime program: anytype) []const u8 {
    if (@TypeOf(program) == type) {
        return shortTypeName(@typeName(program));
    }
    return shortTypeName(@typeName(@TypeOf(program)));
}

fn definedTypeJson(allocator: Allocator, name: []const u8) !std.json.Value {
    var def_obj = std.json.ObjectMap.init(allocator);
    try putString(allocator, &def_obj, "name", name);
    var obj = std.json.ObjectMap.init(allocator);
    try obj.put(try allocator.dupe(u8, "defined"), .{ .object = def_obj });
    return .{ .object = obj };
}

pub const ExampleProgram = struct {
    pub const id = @import("solana_program_sdk").PublicKey.comptimeFromBase58("11111111111111111111111111111111");

    pub const metadata = .{
        .name = "example",
        .version = "0.1.0",
        .spec = "0.1.0",
        .description = "Example program",
        .repository = "https://example.com",
    };

    pub const constants = .{
        .fee_bps = @as(u16, 5),
        .enabled = true,
        .label = "counter",
    };

    pub const events = struct {
        pub const CounterEvent = struct {
            amount: @import("typed_dsl.zig").eventField(u64, .{ .index = true }),
            owner: @import("solana_program_sdk").PublicKey,
        };
    };

    pub const instructions = struct {
        pub const initialize = Instruction(.{ .Accounts = InitializeAccounts, .Args = InitializeArgs });
        pub const close = Instruction(.{ .Accounts = CloseAccounts, .Args = void });
    };

    pub const errors = enum(u32) {
        InvalidAmount = 6000,
    };
};

const CounterData = struct {
    amount: u64,
    authority: @import("solana_program_sdk").PublicKey,
};

const Counter = @import("account.zig").Account(CounterData, .{
    .discriminator = discriminator_mod.accountDiscriminator("Counter"),
    .seeds = &.{ seeds_mod.seed("counter"), seeds_mod.seedAccount("authority") },
    .bump = true,
    .seeds_program = seeds_mod.seedAccount("authority"),
    .has_one = &.{.{ .field = "authority", .target = "authority" }},
    .close = "authority",
    .realloc = .{ .payer = "payer", .zero_init = true },
    .rent_exempt = true,
    .constraint = constraints_mod.constraint("authority.key() == counter.authority"),
    .attrs = &.{@import("attr.zig").attr.mut()},
});

const InitializeAccounts = struct {
    authority: Signer,
    payer: SignerMut,
    counter: Counter,
};

const InitializeArgs = struct {
    amount: u64,
    flag: bool,
    owner: @import("solana_program_sdk").PublicKey,
};

const CloseAccounts = struct {
    authority: Signer,
};

test "idl: discriminator json size" {
    const allocator = std.testing.allocator;
    const json = try discriminatorJson(allocator, "initialize");
    try std.testing.expect(json.array.items.len == 8);
}

test "idl: json generation has core sections" {
    const allocator = std.testing.allocator;
    const json_bytes = try generateJson(allocator, ExampleProgram, .{});
    defer allocator.free(json_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    try std.testing.expect(root.contains("address"));
    try std.testing.expect(root.contains("metadata"));
    try std.testing.expect(root.contains("instructions"));
    try std.testing.expect(root.contains("accounts"));
    try std.testing.expect(root.contains("types"));
    try std.testing.expect(root.contains("errors"));
    try std.testing.expect(root.contains("constants"));
    try std.testing.expect(root.contains("events"));
}

test "idl: instruction args types" {
    const allocator = std.testing.allocator;
    const json_bytes = try generateJson(allocator, ExampleProgram, .{});
    defer allocator.free(json_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const instructions = parsed.value.object.get("instructions").?.array;
    var initialize: ?std.json.ObjectMap = null;
    for (instructions.items) |item| {
        const obj = item.object;
        if (std.mem.eql(u8, obj.get("name").?.string, "initialize")) {
            initialize = obj;
            break;
        }
    }
    try std.testing.expect(initialize != null);
    const args = initialize.?.get("args").?.array;

    try std.testing.expectEqualStrings("amount", args.items[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("u64", args.items[0].object.get("type").?.string);

    try std.testing.expectEqualStrings("flag", args.items[1].object.get("name").?.string);
    try std.testing.expectEqualStrings("bool", args.items[1].object.get("type").?.string);

    try std.testing.expectEqualStrings("owner", args.items[2].object.get("name").?.string);
    try std.testing.expectEqualStrings("pubkey", args.items[2].object.get("type").?.string);
}

test "idl: event and constraints details" {
    const allocator = std.testing.allocator;
    const json_bytes = try generateJson(allocator, ExampleProgram, .{});
    defer allocator.free(json_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const events = root.get("events").?.array;
    try std.testing.expectEqualStrings("CounterEvent", events.items[0].object.get("name").?.string);

    const constants = root.get("constants").?.array;
    try std.testing.expectEqualStrings("fee_bps", constants.items[0].object.get("name").?.string);
    try std.testing.expectEqualStrings("5", constants.items[0].object.get("value").?.string);

    const metadata = root.get("metadata").?.object;
    try std.testing.expectEqualStrings("example", metadata.get("name").?.string);

    const types = root.get("types").?.array;
    var counter_event_type: ?std.json.ObjectMap = null;
    for (types.items) |item| {
        const obj = item.object;
        if (std.mem.eql(u8, obj.get("name").?.string, "CounterEvent")) {
            counter_event_type = obj;
            break;
        }
    }
    try std.testing.expect(counter_event_type != null);
    const event_type_fields = counter_event_type.?.get("type").?.object.get("fields").?.array;
    try std.testing.expect(event_type_fields.items.len > 0);

    const instructions = root.get("instructions").?.array;
    var initialize: ?std.json.ObjectMap = null;
    for (instructions.items) |item| {
        const obj = item.object;
        if (std.mem.eql(u8, obj.get("name").?.string, "initialize")) {
            initialize = obj;
            break;
        }
    }
    try std.testing.expect(initialize != null);
    const accounts = initialize.?.get("accounts").?.array;
    var counter_account: ?std.json.ObjectMap = null;
    for (accounts.items) |item| {
        const obj = item.object;
        if (std.mem.eql(u8, obj.get("name").?.string, "counter")) {
            counter_account = obj;
            break;
        }
    }
    try std.testing.expect(counter_account != null);
    try std.testing.expect(counter_account.?.get("writable").?.bool);
    try std.testing.expect(counter_account.?.get("pda") != null);
    const pda = counter_account.?.get("pda").?.object;
    try std.testing.expect(pda.get("program") != null);
    const program = pda.get("program").?.object;
    try std.testing.expectEqualStrings("account", program.get("kind").?.string);
    try std.testing.expectEqualStrings("authority", program.get("path").?.string);
    try std.testing.expect(counter_account.?.get("relations") != null);
    const relations = counter_account.?.get("relations").?.array;
    try std.testing.expectEqualStrings("authority", relations.items[0].string);
}
