//! Zig implementation of Anchor client code generation
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/mod.rs
//!
//! Generates Zig client modules from comptime program definitions.

const std = @import("std");
const discriminator_mod = @import("discriminator.zig");
const idl_mod = @import("idl.zig");

const Allocator = std.mem.Allocator;
const IdlConfig = idl_mod.IdlConfig;

/// Generate Zig client source code for a program.
pub fn generateZigClient(allocator: Allocator, comptime program: anytype, comptime config: IdlConfig) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    const program_name = idl_mod.shortTypeName(@typeName(@TypeOf(program)));
    var address_buffer: [44]u8 = undefined;
    const address = program.id.toBase58(&address_buffer);

    try output.appendSlice("const std = @import(\"std\");\n");
    try output.appendSlice("const sdk = @import(\"solana_sdk\");\n");
    try output.appendSlice("const client = @import(\"solana_client\");\n\n");
    try output.appendSlice("pub const PublicKey = sdk.PublicKey;\n");
    try output.appendSlice("pub const AccountMeta = sdk.AccountMeta;\n");
    try output.appendSlice("pub const Instruction = sdk.instruction.Instruction;\n");
    try output.appendSlice("pub const RpcClient = client.RpcClient;\n");
    try output.appendSlice("pub const Signature = client.Signature;\n");
    try output.appendSlice("pub const Keypair = client.Keypair;\n");
    try output.appendSlice("pub const AccountInfo = client.AccountInfo;\n");
    try output.appendSlice("pub const AnchorClient = client.anchor;\n\n");

    try appendFmt(&output, allocator, "pub const PROGRAM_ID = sdk.PublicKey.comptimeFromBase58(\"{s}\");\n\n", .{address});
    try appendFmt(&output, allocator, "/// Client for {s}\n", .{program_name});
    try output.appendSlice("pub const Client = struct {\n");
    try output.appendSlice("    allocator: std.mem.Allocator,\n\n");
    try output.appendSlice("    pub fn init(allocator: std.mem.Allocator) Client {\n");
    try output.appendSlice("        return .{ .allocator = allocator };\n");
    try output.appendSlice("    }\n\n");

    const fields = @typeInfo(@TypeOf(program.instructions)).@"struct".fields;
    inline for (fields) |field| {
        const InstructionType = field.type;
        if (!@hasDecl(InstructionType, "Accounts")) {
            @compileError("Instruction type must define Accounts");
        }
        if (!@hasDecl(InstructionType, "Args")) {
            @compileError("Instruction type must define Args");
        }

        const Accounts = InstructionType.Accounts;
        const Args = InstructionType.Args;
        const accounts = idl_mod.extractAccounts(Accounts, config);

        try appendFmt(&output, allocator, "    pub fn {s}(self: *Client", .{field.name});
        for (accounts) |account| {
            try appendFmt(&output, allocator, ", {s}: PublicKey", .{account.name});
        }
        if (!isVoidArgs(Args)) {
            try output.appendSlice(", args: anytype");
        }
        try output.appendSlice(") !Instruction {\n");

        try output.appendSlice("        _ = self;\n");
        try output.appendSlice("        const accounts = [_]AccountMeta{\n");
        for (accounts) |account| {
            try appendFmt(
                &output,
                allocator,
                "            AccountMeta.init({s}, {s}, {s}),\n",
                .{ account.name, boolLiteral(account.is_signer), boolLiteral(account.is_mut) },
            );
        }
        try output.appendSlice("        };\n\n");

        const discriminator = discriminator_mod.instructionDiscriminator(field.name);
        if (isVoidArgs(Args)) {
            try output.appendSlice("        const data = ");
            try appendDiscriminator(&output, allocator, discriminator);
            try output.appendSlice(";\n");
            try output.appendSlice("        return try Instruction.newWithBytes(self.allocator, PROGRAM_ID, data[0..], &accounts);\n");
        } else {
            try output.appendSlice("        const args_bytes = try sdk.borsh.serializeAlloc(self.allocator, @TypeOf(args), args);\n");
            try output.appendSlice("        defer self.allocator.free(args_bytes);\n");
            try output.appendSlice("        var data = try self.allocator.alloc(u8, 8 + args_bytes.len);\n");
            try output.appendSlice("        defer self.allocator.free(data);\n\n");
            try output.appendSlice("        const discriminator = ");
            try appendDiscriminator(&output, allocator, discriminator);
            try output.appendSlice(";\n");
            try output.appendSlice("        @memcpy(data[0..8], discriminator[0..]);\n");
            try output.appendSlice("        @memcpy(data[8..], args_bytes);\n");
            try output.appendSlice("        return try Instruction.newWithBytes(self.allocator, PROGRAM_ID, data, &accounts);\n");
        }

        try output.appendSlice("    }\n\n");
    }

    try output.appendSlice("};\n\n");

    const account_types = collectAccountTypes(program);
    inline for (account_types) |account| {
        try appendFmt(&output, allocator, "pub const {s}Discriminator = ", .{account.name});
        try appendDiscriminator(&output, allocator, account.discriminator);
        try output.appendSlice(";\n");

        try appendFmt(&output, allocator, "pub fn decode{s}(allocator: std.mem.Allocator, comptime T: type, data: []const u8) !T {\n", .{account.name});
        try appendFmt(&output, allocator, "    return AnchorClient.decodeAccountData(allocator, T, data, {s}Discriminator);\n", .{account.name});
        try output.appendSlice("}\n\n");

        try appendFmt(&output, allocator, "pub fn decode{s}FromAccountInfo(allocator: std.mem.Allocator, comptime T: type, info: AccountInfo) !T {\n", .{account.name});
        try appendFmt(&output, allocator, "    return AnchorClient.decodeAccountInfo(allocator, T, info, {s}Discriminator);\n", .{account.name});
        try output.appendSlice("}\n\n");
    }

    try output.appendSlice("pub const ProgramClient = struct {\n");
    try output.appendSlice("    allocator: std.mem.Allocator,\n");
    try output.appendSlice("    rpc: *RpcClient,\n\n");
    try output.appendSlice("    pub fn init(allocator: std.mem.Allocator, rpc: *RpcClient) ProgramClient {\n");
    try output.appendSlice("        return .{ .allocator = allocator, .rpc = rpc };\n");
    try output.appendSlice("    }\n\n");

    inline for (fields) |field| {
        const InstructionType = field.type;
        const Accounts = InstructionType.Accounts;
        const Args = InstructionType.Args;
        const accounts = idl_mod.extractAccounts(Accounts, config);

        try appendFmt(&output, allocator, "    pub fn send{s}(self: *ProgramClient", .{field.name});
        for (accounts) |account| {
            try appendFmt(&output, allocator, ", {s}: PublicKey", .{account.name});
        }
        if (!isVoidArgs(Args)) {
            try output.appendSlice(", args: anytype");
        }
        try output.appendSlice(", signers: []const *const Keypair) !Signature {\n");

        try output.appendSlice("        var builder = Client.init(self.allocator);\n");
        try appendFmt(&output, allocator, "        const ix = try builder.{s}(", .{field.name});
        for (accounts, 0..) |account, index| {
            if (index != 0) {
                try output.appendSlice(", ");
            }
            try appendFmt(&output, allocator, "{s}", .{account.name});
        }
        if (!isVoidArgs(Args)) {
            if (accounts.len > 0) {
                try output.appendSlice(", ");
            }
            try output.appendSlice("args");
        }
        try output.appendSlice(");\n");
        try output.appendSlice("        defer ix.deinit(self.allocator);\n");
        try output.appendSlice("        return AnchorClient.sendInstruction(self.allocator, self.rpc, PROGRAM_ID, ix.accounts, ix.data, signers);\n");
        try output.appendSlice("    }\n\n");
    }

    inline for (account_types) |account| {
        try appendFmt(&output, allocator, "    pub fn get{s}(self: *ProgramClient, comptime T: type, address: PublicKey) !?T {\n", .{account.name});
        try output.appendSlice("        const info = try self.rpc.getAccountInfo(address);\n");
        try output.appendSlice("        if (info == null) return null;\n");
        try appendFmt(&output, allocator, "        return AnchorClient.decodeAccountInfo(self.allocator, T, info.?, {s}Discriminator);\n", .{account.name});
        try output.appendSlice("    }\n\n");
    }

    try output.appendSlice("};\n");

    return output.toOwnedSlice(allocator);
}

fn isVoidArgs(comptime T: type) bool {
    if (T == void) return true;
    const info = @typeInfo(T);
    return info == .@"struct" and info.@"struct".fields.len == 0;
}

fn appendFmt(list: *std.ArrayList(u8), allocator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try list.appendSlice(text);
}

fn appendDiscriminator(list: *std.ArrayList(u8), allocator: Allocator, discriminator: [8]u8) !void {
    try list.appendSlice("[_]u8{");
    for (discriminator, 0..) |byte, index| {
        if (index != 0) {
            try list.appendSlice(", ");
        }
        try appendFmt(list, allocator, "{d}", .{byte});
    }
    try list.appendSlice("}");
}

fn boolLiteral(value: bool) []const u8 {
    return if (value) "true" else "false";
}

const AccountTypeInfo = struct {
    name: []const u8,
    discriminator: [8]u8,
};

fn collectAccountTypes(comptime program: anytype) []const AccountTypeInfo {
    const instructions = @typeInfo(@TypeOf(program.instructions)).@"struct".fields;
    comptime var max: usize = 0;
    inline for (instructions) |field| {
        const InstructionType = field.type;
        const Accounts = InstructionType.Accounts;
        max += @typeInfo(Accounts).@"struct".fields.len;
    }

    if (max == 0) {
        return &[_]AccountTypeInfo{};
    }

    comptime var list: [max]AccountTypeInfo = undefined;
    comptime var len: usize = 0;

    inline for (instructions) |field| {
        const InstructionType = field.type;
        const Accounts = InstructionType.Accounts;
        const fields = @typeInfo(Accounts).@"struct".fields;
        inline for (fields) |account_field| {
            const FieldType = account_field.type;
            if (!isAccountWrapper(FieldType)) continue;

            const name = accountTypeName(FieldType);
            if (containsAccount(list[0..len], name)) continue;
            list[len] = .{
                .name = name,
                .discriminator = FieldType.discriminator,
            };
            len += 1;
        }
    }

    return list[0..len];
}

fn containsAccount(list: []const AccountTypeInfo, name: []const u8) bool {
    for (list) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return false;
}

fn isAccountWrapper(comptime T: type) bool {
    return @hasDecl(T, "DataType") and @hasDecl(T, "discriminator");
}

fn accountTypeName(comptime Wrapper: type) []const u8 {
    const name = idl_mod.shortTypeName(@typeName(Wrapper));
    if (std.mem.indexOf(u8, name, "Account(") != null or std.mem.eql(u8, name, "Account")) {
        return idl_mod.shortTypeName(@typeName(Wrapper.DataType));
    }
    return name;
}

const ExampleProgram = idl_mod.ExampleProgram;

test "codegen: emits program id and instruction builder" {
    const allocator = std.testing.allocator;
    const client_src = try generateZigClient(allocator, ExampleProgram, .{});
    defer allocator.free(client_src);

    try std.testing.expect(std.mem.indexOf(u8, client_src, "PROGRAM_ID") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_src, "Instruction.newWithBytes") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_src, "borsh.serializeAlloc") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_src, "ProgramClient") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_src, "sendInstruction") != null);
    try std.testing.expect(std.mem.indexOf(u8, client_src, "decode") != null);
}
