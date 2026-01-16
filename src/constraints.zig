//! Zig implementation of Anchor constraints
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/constraints.rs
//!
//! Constraints define validation rules for accounts. In Anchor, these are
//! specified via `#[account(...)]` attributes. In sol-anchor-zig, they are
//! defined as struct fields with compile-time configuration.
//!
//! ## Phase 1 Constraints (implemented)
//! - `mut`: Account must be writable
//! - `signer`: Account must sign the transaction
//! - `owner`: Account must be owned by specified program
//! - `address`: Account must have exact public key
//! - `executable`: Account must be executable (for program accounts)
//!
//! ## Future Phases
//! - `rent_exempt`: Rent exemption check (requires Rent sysvar)
//! - `seeds`, `bump`: PDA derivation (Phase 2)
//! - `has_one`, `constraint`: Field validation (Phase 3)
//! - `close`, `realloc`: Account lifecycle (Phase 3)

const std = @import("std");
const anchor_error = @import("error.zig");
const AnchorError = anchor_error.AnchorError;
const sol = @import("solana_program_sdk");

// Import from parent SDK
const Account = sol.account.Account;
const PublicKey = sol.PublicKey;

/// Constraint expression descriptor
///
/// Stored as a string literal and parsed at comptime for runtime validation.
pub const ConstraintExpr = struct {
    expr: []const u8,

    pub fn and_(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " && " ++ other.expr ++ ")" };
    }

    pub fn or_(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " || " ++ other.expr ++ ")" };
    }

    pub fn not_(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "!(" ++ self.expr ++ ")" };
    }

    pub fn eq(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " == " ++ other.expr };
    }

    pub fn ne(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " != " ++ other.expr };
    }

    pub fn gt(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " > " ++ other.expr };
    }

    pub fn ge(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " >= " ++ other.expr };
    }

    pub fn lt(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " < " ++ other.expr };
    }

    pub fn le(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ " <= " ++ other.expr };
    }

    pub fn add(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " + " ++ other.expr ++ ")" };
    }

    pub fn sub(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " - " ++ other.expr ++ ")" };
    }

    pub fn mul(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " * " ++ other.expr ++ ")" };
    }

    pub fn div(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " / " ++ other.expr ++ ")" };
    }

    pub fn mod(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "(" ++ self.expr ++ " % " ++ other.expr ++ ")" };
    }

    pub fn len(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "len(" ++ self.expr ++ ")" };
    }

    pub fn abs(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "abs(" ++ self.expr ++ ")" };
    }

    pub fn min(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "min(" ++ self.expr ++ ", " ++ other.expr ++ ")" };
    }

    pub fn max(self: ConstraintExpr, other: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "max(" ++ self.expr ++ ", " ++ other.expr ++ ")" };
    }

    pub fn clamp(self: ConstraintExpr, min_value: ConstraintExpr, max_value: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "clamp(" ++ self.expr ++ ", " ++ min_value.expr ++ ", " ++ max_value.expr ++ ")" };
    }

    pub fn startsWith(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "starts_with(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn endsWith(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "ends_with(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn contains(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "contains(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn startsWithCi(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "starts_with_ci(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn endsWithCi(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "ends_with_ci(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn containsCi(self: ConstraintExpr, comptime needle: []const u8) ConstraintExpr {
        return .{ .expr = "contains_ci(" ++ self.expr ++ ", " ++ quoteLiteral(needle) ++ ")" };
    }

    pub fn isEmpty(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "is_empty(" ++ self.expr ++ ")" };
    }

    pub fn key(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = self.expr ++ ".key()" };
    }

    pub fn asInt(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "as_int(" ++ self.expr ++ ")" };
    }

    pub fn asBytes(self: ConstraintExpr) ConstraintExpr {
        return .{ .expr = "as_bytes(" ++ self.expr ++ ")" };
    }
};

/// Define a constraint expression.
///
/// Example:
/// ```zig
/// .constraint = anchor.constraint("authority.key() == vault.authority")
/// ```
pub fn constraint(comptime expr: []const u8) ConstraintExpr {
    if (expr.len == 0) {
        @compileError("constraint expression cannot be empty");
    }
    return .{ .expr = expr };
}

fn quoteLiteral(comptime value: []const u8) []const u8 {
    comptime {
        for (value) |ch| {
            if (ch == '"' or ch == '\\') {
                @compileError("constraint string literal does not support quotes or escapes");
            }
        }
    }
    return "\"" ++ value ++ "\"";
}

fn hexEncode(comptime bytes: [32]u8) []const u8 {
    const hex_chars = "0123456789abcdef";
    comptime var out: [64]u8 = undefined;
    comptime var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const b = bytes[i];
        out[i * 2] = hex_chars[b >> 4];
        out[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return out[0..];
}

fn hexToNibble(comptime value: u8) u8 {
    return switch (value) {
        '0'...'9' => value - '0',
        'a'...'f' => value - 'a' + 10,
        'A'...'F' => value - 'A' + 10,
        else => @compileError("constraint pubkey_bytes requires hex string"),
    };
}

fn hexDecode32(comptime value: []const u8) [32]u8 {
    if (value.len != 64) {
        @compileError("constraint pubkey_bytes requires 64 hex chars");
    }
    comptime var out: [32]u8 = undefined;
    comptime var i: usize = 0;
    while (i < 32) : (i += 1) {
        const hi = hexToNibble(value[i * 2]);
        const lo = hexToNibble(value[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out;
}

fn hexDecode(comptime value: []const u8) []const u8 {
    if (value.len % 2 != 0) {
        @compileError("constraint bytes_hex requires even-length hex string");
    }
    comptime var out: [value.len / 2]u8 = undefined;
    comptime var i: usize = 0;
    while (i < out.len) : (i += 1) {
        const hi = hexToNibble(value[i * 2]);
        const lo = hexToNibble(value[i * 2 + 1]);
        out[i] = (hi << 4) | lo;
    }
    return out[0..];
}

/// Typed constraint expression builder.
pub const constraint_typed = struct {
    pub fn field(comptime name: []const u8) ConstraintExpr {
        return .{ .expr = name };
    }

    pub fn int_(comptime value: anytype) ConstraintExpr {
        return .{ .expr = std.fmt.comptimePrint("{d}", .{value}) };
    }

    pub fn bool_(comptime value: bool) ConstraintExpr {
        return .{ .expr = if (value) "true" else "false" };
    }

    pub fn bytes(comptime value: []const u8) ConstraintExpr {
        return .{ .expr = quoteLiteral(value) };
    }

    pub fn pubkey(comptime value: anytype) ConstraintExpr {
        const T = @TypeOf(value);
        if (T == PublicKey) {
            return pubkeyValue(value);
        }
        if (@typeInfo(T) == .array) {
            const array = @typeInfo(T).array;
            if (array.child == u8 and array.len == 32) {
                return pubkeyBytes(value);
            }
        }
        if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice and @typeInfo(T).pointer.child == u8) {
            return .{ .expr = "pubkey(" ++ quoteLiteral(value) ++ ")" };
        }
        @compileError("constraint_typed.pubkey expects PublicKey, [32]u8, or base58 string");
    }

    pub fn bytesFromHex(comptime value: []const u8) ConstraintExpr {
        return .{ .expr = "bytes_hex(" ++ quoteLiteral(value) ++ ")" };
    }

    pub fn pubkeyBytes(comptime bytes: [32]u8) ConstraintExpr {
        return .{ .expr = "pubkey_bytes(" ++ quoteLiteral(hexEncode(bytes)) ++ ")" };
    }

    pub fn pubkeyValue(comptime key: PublicKey) ConstraintExpr {
        return pubkeyBytes(key.bytes);
    }
};

const ValueKind = enum {
    pubkey,
    int,
    bool,
    bytes,
    invalid,
};

const Value = union(ValueKind) {
    pubkey: [32]u8,
    int: i128,
    bool: bool,
    bytes: []const u8,
    invalid: void,
};

const UnaryOp = enum {
    not,
    neg,
};

const BinaryOp = enum {
    eq,
    ne,
    gt,
    ge,
    lt,
    le,
    add,
    sub,
    mul,
    div,
    mod,
    and_op,
    or_op,
};

const Access = struct {
    parts: [8][]const u8,
    len: usize,
    use_key: bool,
};

const Operand = union(enum) {
    access: Access,
    int: i128,
    bool: bool,
    bytes: []const u8,
    pubkey: [32]u8,
};

const UnaryExpr = struct {
    op: UnaryOp,
    expr: usize,
};

const BinaryExpr = struct {
    op: BinaryOp,
    lhs: usize,
    rhs: usize,
};

const CallKind = enum {
    len,
    abs,
    starts_with,
    ends_with,
    contains,
    starts_with_ci,
    ends_with_ci,
    contains_ci,
    is_empty,
    min,
    max,
    clamp,
    as_int,
    as_bytes,
};

const CallExpr = struct {
    kind: CallKind,
    args: [3]usize,
    len: usize,
};

const Node = union(enum) {
    value: Operand,
    unary: UnaryExpr,
    binary: BinaryExpr,
    call: CallExpr,
};

const ParsedExpr = struct {
    nodes: [MAX_NODES]Node,
    len: usize,
    root: usize,
};

const MAX_NODES: usize = 64;

const ExprParser = struct {
    input: []const u8,
    index: usize,
    nodes: [MAX_NODES]Node,
    len: usize,

    fn init(comptime input: []const u8) ExprParser {
        return .{ .input = input, .index = 0, .nodes = undefined, .len = 0 };
    }

    fn eof(self: *const ExprParser) bool {
        return self.index >= self.input.len;
    }

    fn peek(self: *const ExprParser) ?u8 {
        if (self.eof()) return null;
        return self.input[self.index];
    }

    fn skipWs(self: *ExprParser) void {
        while (self.peek()) |c| {
            if (c != ' ' and c != '\n' and c != '\t' and c != '\r') break;
            self.index += 1;
        }
    }

    fn consumeChar(self: *ExprParser, comptime expected: u8) bool {
        if (self.peek() == expected) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn consumeSlice(self: *ExprParser, comptime expected: []const u8) bool {
        if (self.index + expected.len > self.input.len) return false;
        if (!std.mem.eql(u8, self.input[self.index .. self.index + expected.len], expected)) return false;
        self.index += expected.len;
        return true;
    }

    fn expectChar(self: *ExprParser, comptime expected: u8) void {
        if (!self.consumeChar(expected)) {
            @compileError("constraint parse error: expected character");
        }
    }

    fn expectEof(self: *ExprParser) void {
        if (!self.eof()) {
            @compileError("constraint parse error: trailing input");
        }
    }

    fn isIdentChar(c: u8) bool {
        return std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '_';
    }

    fn parseIdent(self: *ExprParser) []const u8 {
        const start = self.index;
        while (self.peek()) |c| {
            if (!isIdentChar(c)) break;
            self.index += 1;
        }
        if (self.index == start) {
            @compileError("constraint parse error: expected identifier");
        }
        return self.input[start..self.index];
    }

    fn parseInt(self: *ExprParser) i128 {
        const start = self.index;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            self.index += 1;
        }
        if (self.index == start) {
            @compileError("constraint parse error: expected integer");
        }
        return std.fmt.parseInt(i128, self.input[start..self.index], 10) catch {
            @compileError("constraint parse error: invalid integer");
        };
    }

    fn addNode(self: *ExprParser, node: Node) usize {
        if (self.len >= self.nodes.len) {
            @compileError("constraint parse error: expression too large");
        }
        self.nodes[self.len] = node;
        self.len += 1;
        return self.len - 1;
    }

    fn parseStringLiteral(self: *ExprParser) []const u8 {
        self.expectChar('"');
        const start = self.index;
        while (self.peek()) |c| {
            if (c == '"') {
                const value = self.input[start..self.index];
                self.index += 1;
                return value;
            }
            if (c == '\\') {
                @compileError("constraint parse error: string escapes not supported");
            }
            self.index += 1;
        }
        @compileError("constraint parse error: unterminated string literal");
    }

    fn parseAccessFromIdent(self: *ExprParser, ident: []const u8) Operand {
        var parts: [8][]const u8 = undefined;
        var count: usize = 0;
        parts[count] = ident;
        count += 1;

        var use_key = false;
        while (true) {
            self.skipWs();
            if (!self.consumeChar('.')) break;
            self.skipWs();
            const next = self.parseIdent();
            if (std.mem.eql(u8, next, "key")) {
                self.skipWs();
                self.expectChar('(');
                self.skipWs();
                self.expectChar(')');
                use_key = true;
                break;
            }
            if (count >= parts.len) {
                @compileError("constraint parse error: too many access segments");
            }
            parts[count] = next;
            count += 1;
        }

        return .{ .access = .{ .parts = parts, .len = count, .use_key = use_key } };
    }

    fn parseCall(self: *ExprParser, ident: []const u8) usize {
        const kind: CallKind = if (std.mem.eql(u8, ident, "len"))
            .len
        else if (std.mem.eql(u8, ident, "abs"))
            .abs
        else if (std.mem.eql(u8, ident, "starts_with"))
            .starts_with
        else if (std.mem.eql(u8, ident, "ends_with"))
            .ends_with
        else if (std.mem.eql(u8, ident, "contains"))
            .contains
        else if (std.mem.eql(u8, ident, "starts_with_ci"))
            .starts_with_ci
        else if (std.mem.eql(u8, ident, "ends_with_ci"))
            .ends_with_ci
        else if (std.mem.eql(u8, ident, "contains_ci"))
            .contains_ci
        else if (std.mem.eql(u8, ident, "is_empty"))
            .is_empty
        else if (std.mem.eql(u8, ident, "min"))
            .min
        else if (std.mem.eql(u8, ident, "max"))
            .max
        else if (std.mem.eql(u8, ident, "clamp"))
            .clamp
        else if (std.mem.eql(u8, ident, "as_int"))
            .as_int
        else if (std.mem.eql(u8, ident, "as_bytes"))
            .as_bytes
        else
            @compileError("constraint parse error: unknown function");

        self.skipWs();
        if (self.consumeChar(')')) {
            @compileError("constraint parse error: expected function arguments");
        }

        const first = self.parseUnary();
        var args: [3]usize = .{ first, 0, 0 };
        var arg_len: usize = 1;

        self.skipWs();
        if (kind == .starts_with or kind == .ends_with or kind == .contains or kind == .starts_with_ci or kind == .ends_with_ci or kind == .contains_ci or kind == .min or kind == .max or kind == .clamp) {
            self.expectChar(',');
            const second = self.parseUnary();
            args[1] = second;
            arg_len = 2;
            self.skipWs();
        }
        if (kind == .clamp) {
            self.expectChar(',');
            const third = self.parseUnary();
            args[2] = third;
            arg_len = 3;
            self.skipWs();
        }

        self.expectChar(')');
        return self.addNode(.{ .call = .{ .kind = kind, .args = args, .len = arg_len } });
    }

    fn parsePrimary(self: *ExprParser) usize {
        self.skipWs();
        if (self.consumeChar('(')) {
            const expr = self.parseExpr();
            self.skipWs();
            self.expectChar(')');
            return expr;
        }
        if (self.peek()) |c| {
            if (c == '"') {
                const literal = self.parseStringLiteral();
                return self.addNode(.{ .value = .{ .bytes = literal } });
            }
            if (std.ascii.isDigit(c)) {
                return self.addNode(.{ .value = .{ .int = self.parseInt() } });
            }
        }

        const ident = self.parseIdent();
        if (std.mem.eql(u8, ident, "true")) return self.addNode(.{ .value = .{ .bool = true } });
        if (std.mem.eql(u8, ident, "false")) return self.addNode(.{ .value = .{ .bool = false } });

        self.skipWs();
        if (std.mem.eql(u8, ident, "pubkey") and self.consumeChar('(')) {
            self.skipWs();
            const encoded = self.parseStringLiteral();
            self.skipWs();
            self.expectChar(')');
            const key = comptime PublicKey.comptimeFromBase58(encoded);
            return self.addNode(.{ .value = .{ .pubkey = key.bytes } });
        }
        if (std.mem.eql(u8, ident, "pubkey_bytes") and self.consumeChar('(')) {
            self.skipWs();
            const encoded = self.parseStringLiteral();
            self.skipWs();
            self.expectChar(')');
            const bytes = comptime hexDecode32(encoded);
            return self.addNode(.{ .value = .{ .pubkey = bytes } });
        }
        if (std.mem.eql(u8, ident, "bytes_hex") and self.consumeChar('(')) {
            self.skipWs();
            const encoded = self.parseStringLiteral();
            self.skipWs();
            self.expectChar(')');
            const bytes = comptime hexDecode(encoded);
            return self.addNode(.{ .value = .{ .bytes = bytes } });
        }
        if (self.consumeChar('(')) {
            return self.parseCall(ident);
        }

        const operand = self.parseAccessFromIdent(ident);
        return self.addNode(.{ .value = operand });
    }

    fn parseUnary(self: *ExprParser) usize {
        self.skipWs();
        if (self.consumeChar('!')) {
            const child = self.parseUnary();
            return self.addNode(.{ .unary = .{ .op = .not, .expr = child } });
        }
        if (self.consumeChar('-')) {
            const child = self.parseUnary();
            return self.addNode(.{ .unary = .{ .op = .neg, .expr = child } });
        }
        return self.parsePrimary();
    }

    fn parseMul(self: *ExprParser) usize {
        var left = self.parseUnary();
        while (true) {
            self.skipWs();
            const op: ?BinaryOp = if (self.consumeChar('*'))
                .mul
            else if (self.consumeChar('/'))
                .div
            else if (self.consumeChar('%'))
                .mod
            else
                null;
            if (op == null) break;
            const right = self.parseUnary();
            left = self.addNode(.{ .binary = .{ .op = op.?, .lhs = left, .rhs = right } });
        }
        return left;
    }

    fn parseAdd(self: *ExprParser) usize {
        var left = self.parseMul();
        while (true) {
            self.skipWs();
            const op: ?BinaryOp = if (self.consumeChar('+'))
                .add
            else if (self.consumeChar('-'))
                .sub
            else
                null;
            if (op == null) break;
            const right = self.parseMul();
            left = self.addNode(.{ .binary = .{ .op = op.?, .lhs = left, .rhs = right } });
        }
        return left;
    }

    fn parseCompareOp(self: *ExprParser) ?BinaryOp {
        self.skipWs();
        if (self.consumeChar('=')) {
            if (!self.consumeChar('=')) {
                @compileError("constraint parse error: expected ==");
            }
            return .eq;
        }
        if (self.consumeChar('!')) {
            if (!self.consumeChar('=')) {
                @compileError("constraint parse error: expected !=");
            }
            return .ne;
        }
        if (self.consumeChar('>')) {
            if (self.consumeChar('=')) return .ge;
            return .gt;
        }
        if (self.consumeChar('<')) {
            if (self.consumeChar('=')) return .le;
            return .lt;
        }
        return null;
    }

    fn parseCompare(self: *ExprParser) usize {
        var left = self.parseAdd();
        while (true) {
            const op = self.parseCompareOp() orelse break;
            const right = self.parseAdd();
            left = self.addNode(.{ .binary = .{ .op = op, .lhs = left, .rhs = right } });
        }
        return left;
    }

    fn parseAnd(self: *ExprParser) usize {
        var left = self.parseCompare();
        while (true) {
            self.skipWs();
            if (!self.consumeSlice("&&")) break;
            const right = self.parseCompare();
            left = self.addNode(.{ .binary = .{ .op = .and_op, .lhs = left, .rhs = right } });
        }
        return left;
    }

    fn parseOr(self: *ExprParser) usize {
        var left = self.parseAnd();
        while (true) {
            self.skipWs();
            if (!self.consumeSlice("||")) break;
            const right = self.parseAnd();
            left = self.addNode(.{ .binary = .{ .op = .or_op, .lhs = left, .rhs = right } });
        }
        return left;
    }

    fn parseExpr(self: *ExprParser) usize {
        return self.parseOr();
    }
};

fn parseConstraint(comptime expr: []const u8) ParsedExpr {
    comptime var parser = ExprParser.init(expr);
    const root = parser.parseExpr();
    parser.skipWs();
    parser.expectEof();
    return .{ .nodes = parser.nodes, .len = parser.len, .root = root };
}

fn hasField(comptime T: type, comptime name: []const u8) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return true;
    }
    return false;
}

fn fieldTypeByName(comptime T: type, comptime name: []const u8) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct") return null;
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field.type;
    }
    return null;
}

fn unwrapOptionalType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .optional) {
        return info.optional.child;
    }
    return T;
}

fn unwrapPointerType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer) {
        if (info.pointer.size == .one) {
            return info.pointer.child;
        }
        return T;
    }
    return T;
}

fn isPubkeyLike(comptime T: type) bool {
    const Clean = unwrapPointerType(unwrapOptionalType(T));
    if (Clean == PublicKey) return true;
    if (@typeInfo(Clean) == .array) {
        const array = @typeInfo(Clean).array;
        return array.child == u8 and array.len == 32;
    }
    return false;
}

fn isIntType(comptime T: type) bool {
    return @typeInfo(unwrapPointerType(unwrapOptionalType(T))) == .int;
}

fn isBoolType(comptime T: type) bool {
    return unwrapPointerType(unwrapOptionalType(T)) == bool;
}

fn isBytesType(comptime T: type) bool {
    const Clean = unwrapOptionalType(T);
    const info = @typeInfo(Clean);
    if (info == .pointer and info.pointer.size == .slice) {
        return info.pointer.child == u8;
    }
    if (info == .array) {
        return info.array.child == u8 and info.array.len != 32;
    }
    return false;
}

fn accessValueType(
    comptime access: Access,
    comptime account_name: []const u8,
    comptime Accounts: type,
) type {
    const parts = access.parts;
    const len = access.len;
    comptime var current: type = Accounts;
    comptime var index: usize = 0;

    if (len > 0 and std.mem.eql(u8, parts[0], account_name)) {
        const FieldType = fieldTypeByName(Accounts, parts[0]) orelse {
            @compileError("constraint access references unknown account: " ++ parts[0]);
        };
        current = FieldType;
        index = 1;
    }

    while (index < len) : (index += 1) {
        const name = parts[index];
        const Clean = unwrapPointerType(unwrapOptionalType(current));
        if (@hasDecl(Clean, "DataType")) {
            const DataType = Clean.DataType;
            if (hasField(DataType, name)) {
                current = fieldTypeByName(DataType, name).?;
                continue;
            }
        }
        if (std.mem.eql(u8, name, "__owner") and @hasDecl(Clean, "owner")) {
            current = PublicKey;
            continue;
        }
        if (hasField(Clean, name)) {
            current = fieldTypeByName(Clean, name).?;
            continue;
        }
        @compileError("constraint access references unknown field: " ++ name);
    }

    if (access.use_key) {
        const Clean = unwrapPointerType(unwrapOptionalType(current));
        if (!@hasDecl(Clean, "key")) {
            @compileError("constraint key() requires key() method");
        }
        return PublicKey;
    }

    return current;
}

fn operandKind(
    comptime operand: Operand,
    comptime account_name: []const u8,
    comptime Accounts: type,
) ValueKind {
    return switch (operand) {
        .int => .int,
        .bool => .bool,
        .bytes => .bytes,
        .pubkey => .pubkey,
        .access => |access| blk: {
            const T = accessValueType(access, account_name, Accounts);
            if (isPubkeyLike(T)) break :blk .pubkey;
            if (isIntType(T)) break :blk .int;
            if (isBoolType(T)) break :blk .bool;
            if (isBytesType(T)) break :blk .bytes;
            @compileError("constraint access type not supported");
        },
    };
}

fn exprKind(
    comptime expr: ParsedExpr,
    comptime index: usize,
    comptime account_name: []const u8,
    comptime Accounts: type,
) ValueKind {
    return switch (expr.nodes[index]) {
        .value => |operand| operandKind(operand, account_name, Accounts),
        .unary => |unary| blk: {
            const child_kind = exprKind(expr, unary.expr, account_name, Accounts);
            switch (unary.op) {
                .not => {
                    if (child_kind != .bool) {
                        @compileError("constraint unary operator requires bool");
                    }
                    break :blk .bool;
                },
                .neg => {
                    if (child_kind != .int) {
                        @compileError("constraint unary negation requires integer");
                    }
                    break :blk .int;
                },
            }
        },
        .binary => |binary| blk: {
            const lhs_kind = exprKind(expr, binary.lhs, account_name, Accounts);
            const rhs_kind = exprKind(expr, binary.rhs, account_name, Accounts);

            switch (binary.op) {
                .and_op, .or_op => {
                    if (lhs_kind != .bool or rhs_kind != .bool) {
                        @compileError("constraint logical operator requires bool operands");
                    }
                    break :blk .bool;
                },
                .eq, .ne => {
                    if (lhs_kind == .invalid or rhs_kind == .invalid) {
                        @compileError("constraint contains invalid operand");
                    }
                    if (lhs_kind != rhs_kind) {
                        @compileError("constraint operands must have matching types");
                    }
                    break :blk .bool;
                },
                .gt, .ge, .lt, .le => {
                    if (lhs_kind != .int or rhs_kind != .int) {
                        @compileError("constraint comparison requires integer operands");
                    }
                    break :blk .bool;
                },
                .add, .sub, .mul, .div, .mod => {
                    if (lhs_kind != .int or rhs_kind != .int) {
                        @compileError("constraint arithmetic requires integer operands");
                    }
                    break :blk .int;
                },
            }
        },
        .call => |call| blk: {
            switch (call.kind) {
                .len => {
                    const arg_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    if (arg_kind != .bytes) {
                        @compileError("constraint len() requires byte slice");
                    }
                    break :blk .int;
                },
                .abs => {
                    const arg_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    if (arg_kind != .int) {
                        @compileError("constraint abs() requires integer");
                    }
                    break :blk .int;
                },
                .starts_with, .ends_with, .contains, .starts_with_ci, .ends_with_ci, .contains_ci => {
                    const lhs_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    const rhs_kind = exprKind(expr, call.args[1], account_name, Accounts);
                    if (lhs_kind != .bytes or rhs_kind != .bytes) {
                        @compileError("constraint string helper requires byte slices");
                    }
                    break :blk .bool;
                },
                .is_empty => {
                    const arg_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    if (arg_kind != .bytes) {
                        @compileError("constraint is_empty() requires byte slice");
                    }
                    break :blk .bool;
                },
                .min, .max => {
                    const lhs_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    const rhs_kind = exprKind(expr, call.args[1], account_name, Accounts);
                    if (lhs_kind != .int or rhs_kind != .int) {
                        @compileError("constraint min/max requires integer operands");
                    }
                    break :blk .int;
                },
                .clamp => {
                    const value_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    const min_kind = exprKind(expr, call.args[1], account_name, Accounts);
                    const max_kind = exprKind(expr, call.args[2], account_name, Accounts);
                    if (value_kind != .int or min_kind != .int or max_kind != .int) {
                        @compileError("constraint clamp() requires integer operands");
                    }
                    break :blk .int;
                },
                .as_int => {
                    const arg_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    if (arg_kind != .int) {
                        @compileError("constraint as_int() requires integer operand");
                    }
                    break :blk .int;
                },
                .as_bytes => {
                    const arg_kind = exprKind(expr, call.args[0], account_name, Accounts);
                    if (arg_kind != .bytes) {
                        @compileError("constraint as_bytes() requires byte slice");
                    }
                    break :blk .bytes;
                },
            }
        },
    };
}

fn validateConstraintTypes(
    comptime expr: ParsedExpr,
    comptime account_name: []const u8,
    comptime Accounts: type,
) void {
    const kind = exprKind(expr, expr.root, account_name, Accounts);
    if (kind != .bool) {
        @compileError("constraint expression must evaluate to bool");
    }
}

fn valueFromAny(value: anytype) Value {
    const T = @TypeOf(value);
    if (@typeInfo(T) == .optional) {
        if (value == null) return .{ .invalid = {} };
        return valueFromAny(value.?);
    }
    if (@typeInfo(T) == .pointer) {
        const info = @typeInfo(T).pointer;
        if (info.size == .slice) {
            if (info.child == u8) {
                return .{ .bytes = value };
            }
            @compileError("constraint value type not supported: " ++ @typeName(T));
        }
        if (info.size == .one) {
            if (@typeInfo(info.child) == .array) {
                const array = @typeInfo(info.child).array;
                if (array.child == u8 and array.len != 32) {
                    return .{ .bytes = value.*[0..] };
                }
            }
            return valueFromAny(value.*);
        }
        @compileError("constraint value type not supported: " ++ @typeName(T));
    }

    if (T == PublicKey) {
        return .{ .pubkey = value.bytes };
    }
    if (@typeInfo(T) == .array) {
        const array = @typeInfo(T).array;
        if (array.child == u8 and array.len == 32) {
            return .{ .pubkey = value };
        }
        if (array.child == u8) {
            @compileError("constraint value type not supported: " ++ @typeName(T));
        }
    }
    if (@typeInfo(T) == .int) {
        return .{ .int = @intCast(value) };
    }
    if (T == bool) {
        return .{ .bool = value };
    }
    if (@typeInfo(T) == .pointer and @typeInfo(T).pointer.size == .slice and @typeInfo(T).pointer.child == u8) {
        return .{ .bytes = value };
    }

    @compileError("constraint value type not supported: " ++ @typeName(T));
}

fn resolveAccessValue(
    comptime access: Access,
    comptime account_name: []const u8,
    accounts: anytype,
) Value {
    const parts = access.parts;
    const len = access.len;
    const start_index: usize = if (len > 0 and std.mem.eql(u8, parts[0], account_name)) 1 else 0;
    if (start_index == 1) {
        return resolveAccessValueAt(access, @field(accounts, parts[0]), 1);
    }
    return resolveAccessValueAt(access, accounts, 0);
}

fn resolveAccessValueAt(
    comptime access: Access,
    current: anytype,
    comptime index: usize,
) Value {
    if (index >= access.len) {
        if (access.use_key) {
            const CleanType = @TypeOf(current);
            if (!@hasDecl(CleanType, "key")) {
                @compileError("constraint key() requires key() method");
            }
            return valueFromAny(current.key().*);
        }
        return valueFromAny(current);
    }

    const name = access.parts[index];
    var next = current;
    const CurrentType = @TypeOf(next);
    if (@typeInfo(CurrentType) == .optional) {
        if (next == null) {
            return .{ .invalid = {} };
        }
        next = next.?;
    }
    if (@typeInfo(@TypeOf(next)) == .pointer) {
        const ptr_info = @typeInfo(@TypeOf(next)).pointer;
        if (ptr_info.size == .one) {
            next = next.*;
        }
    }

    const CleanType = @TypeOf(next);
    if (comptime @hasDecl(CleanType, "DataType")) {
        const DataType = CleanType.DataType;
        if (comptime hasField(DataType, name)) {
            const field_ptr = &@field(next.data.*, name);
            const field_type = @TypeOf(field_ptr.*);
            if (@typeInfo(field_type) == .array and @typeInfo(field_type).array.child == u8 and @typeInfo(field_type).array.len != 32) {
                return resolveAccessValueAt(access, field_ptr, index + 1);
            }
            return resolveAccessValueAt(access, field_ptr.*, index + 1);
        }
    }
    if (comptime std.mem.eql(u8, name, "__owner") and @hasDecl(CleanType, "owner")) {
        return resolveAccessValueAt(access, next.owner(), index + 1);
    }
    if (comptime hasField(CleanType, name)) {
        const field_ptr = &@field(next, name);
        const field_type = @TypeOf(field_ptr.*);
        if (@typeInfo(field_type) == .array and @typeInfo(field_type).array.child == u8 and @typeInfo(field_type).array.len != 32) {
            return resolveAccessValueAt(access, field_ptr, index + 1);
        }
        return resolveAccessValueAt(access, field_ptr.*, index + 1);
    }

    @compileError("constraint access references unknown field: " ++ name);
}

fn evalOperand(
    comptime operand: Operand,
    comptime account_name: []const u8,
    accounts: anytype,
) Value {
    return switch (operand) {
        .int => |value| .{ .int = value },
        .bool => |value| .{ .bool = value },
        .bytes => |value| .{ .bytes = value },
        .pubkey => |value| .{ .pubkey = value },
        .access => |access| resolveAccessValue(access, account_name, accounts),
    };
}

fn compareValues(lhs: Value, op: BinaryOp, rhs: Value) bool {
    return switch (lhs) {
        .invalid => false,
        .pubkey => |l| switch (rhs) {
            .pubkey => |r| switch (op) {
                .eq => std.mem.eql(u8, &l, &r),
                .ne => !std.mem.eql(u8, &l, &r),
                else => false,
            },
            else => false,
        },
        .int => |l| switch (rhs) {
            .int => |r| switch (op) {
                .eq => l == r,
                .ne => l != r,
                .gt => l > r,
                .ge => l >= r,
                .lt => l < r,
                .le => l <= r,
                else => false,
            },
            else => false,
        },
        .bool => |l| switch (rhs) {
            .bool => |r| switch (op) {
                .eq => l == r,
                .ne => l != r,
                else => false,
            },
            else => false,
        },
        .bytes => |l| switch (rhs) {
            .bytes => |r| switch (op) {
                .eq => std.mem.eql(u8, l, r),
                .ne => !std.mem.eql(u8, l, r),
                else => false,
            },
            else => false,
        },
    };
}

fn toLowerAscii(byte: u8) u8 {
    if (byte >= 'A' and byte <= 'Z') {
        return byte + 32;
    }
    return byte;
}

fn startsWithCi(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (needle, 0..) |ch, i| {
        if (toLowerAscii(haystack[i]) != toLowerAscii(ch)) return false;
    }
    return true;
}

fn endsWithCi(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    const start = haystack.len - needle.len;
    for (needle, 0..) |ch, i| {
        if (toLowerAscii(haystack[start + i]) != toLowerAscii(ch)) return false;
    }
    return true;
}

fn containsCi(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (startsWithCi(haystack[i..], needle)) return true;
    }
    return false;
}

fn evalExpr(
    comptime expr: ParsedExpr,
    comptime index: usize,
    comptime account_name: []const u8,
    accounts: anytype,
) Value {
    return switch (expr.nodes[index]) {
        .value => |operand| evalOperand(operand, account_name, accounts),
        .unary => |unary| blk: {
            const value = evalExpr(expr, unary.expr, account_name, accounts);
            switch (unary.op) {
                .not => switch (value) {
                    .bool => |b| break :blk .{ .bool = !b },
                    else => return .{ .invalid = {} },
                },
                .neg => switch (value) {
                    .int => |i| break :blk .{ .int = -i },
                    else => return .{ .invalid = {} },
                },
            }
        },
        .binary => |binary| blk: {
            if (binary.op == .and_op or binary.op == .or_op) {
                const lhs = evalExpr(expr, binary.lhs, account_name, accounts);
                const l = switch (lhs) {
                    .bool => |value| value,
                    else => return .{ .invalid = {} },
                };
                if (binary.op == .and_op and !l) {
                    break :blk .{ .bool = false };
                }
                if (binary.op == .or_op and l) {
                    break :blk .{ .bool = true };
                }
                const rhs = evalExpr(expr, binary.rhs, account_name, accounts);
                const r = switch (rhs) {
                    .bool => |value| value,
                    else => return .{ .invalid = {} },
                };
                break :blk .{ .bool = if (binary.op == .and_op) (l and r) else (l or r) };
            }
            if (binary.op == .add or binary.op == .sub or binary.op == .mul or binary.op == .div or binary.op == .mod) {
                const lhs = evalExpr(expr, binary.lhs, account_name, accounts);
                const rhs = evalExpr(expr, binary.rhs, account_name, accounts);
                const l = switch (lhs) {
                    .int => |value| value,
                    else => return .{ .invalid = {} },
                };
                const r = switch (rhs) {
                    .int => |value| value,
                    else => return .{ .invalid = {} },
                };
                if ((binary.op == .div or binary.op == .mod) and r == 0) {
                    return .{ .invalid = {} };
                }
                const result = switch (binary.op) {
                    .add => l + r,
                    .sub => l - r,
                    .mul => l * r,
                    .div => @divTrunc(l, r),
                    .mod => @mod(l, r),
                    else => unreachable,
                };
                break :blk .{ .int = result };
            }
            const lhs = evalExpr(expr, binary.lhs, account_name, accounts);
            const rhs = evalExpr(expr, binary.rhs, account_name, accounts);
            return .{ .bool = compareValues(lhs, binary.op, rhs) };
        },
        .call => |call| blk: {
            switch (call.kind) {
                .len => {
                    const arg = evalExpr(expr, call.args[0], account_name, accounts);
                    return switch (arg) {
                        .bytes => |value| .{ .int = @intCast(value.len) },
                        else => .{ .invalid = {} },
                    };
                },
                .abs => {
                    const arg = evalExpr(expr, call.args[0], account_name, accounts);
                    return switch (arg) {
                        .int => |value| .{ .int = if (value < 0) -value else value },
                        else => .{ .invalid = {} },
                    };
                },
                .starts_with => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = std.mem.startsWith(u8, l, r) };
                },
                .ends_with => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = std.mem.endsWith(u8, l, r) };
                },
                .contains => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = std.mem.indexOf(u8, l, r) != null };
                },
                .starts_with_ci => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = startsWithCi(l, r) };
                },
                .ends_with_ci => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = endsWithCi(l, r) };
                },
                .contains_ci => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .bytes => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .bool = containsCi(l, r) };
                },
                .is_empty => {
                    const arg = evalExpr(expr, call.args[0], account_name, accounts);
                    return switch (arg) {
                        .bytes => |value| .{ .bool = value.len == 0 },
                        else => .{ .invalid = {} },
                    };
                },
                .min => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .int => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .int => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .int = if (l < r) l else r };
                },
                .max => {
                    const left = evalExpr(expr, call.args[0], account_name, accounts);
                    const right = evalExpr(expr, call.args[1], account_name, accounts);
                    const l = switch (left) {
                        .int => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    const r = switch (right) {
                        .int => |value| value,
                        else => return .{ .invalid = {} },
                    };
                    break :blk .{ .int = if (l > r) l else r };
                },
                .clamp => {
                    const value = evalExpr(expr, call.args[0], account_name, accounts);
                    const min_value = evalExpr(expr, call.args[1], account_name, accounts);
                    const max_value = evalExpr(expr, call.args[2], account_name, accounts);
                    const v = switch (value) {
                        .int => |val| val,
                        else => return .{ .invalid = {} },
                    };
                    const min_v = switch (min_value) {
                        .int => |val| val,
                        else => return .{ .invalid = {} },
                    };
                    const max_v = switch (max_value) {
                        .int => |val| val,
                        else => return .{ .invalid = {} },
                    };
                    const clamped = if (v < min_v) min_v else if (v > max_v) max_v else v;
                    break :blk .{ .int = clamped };
                },
                .as_int => {
                    const arg = evalExpr(expr, call.args[0], account_name, accounts);
                    return switch (arg) {
                        .int => |value| .{ .int = value },
                        else => .{ .invalid = {} },
                    };
                },
                .as_bytes => {
                    const arg = evalExpr(expr, call.args[0], account_name, accounts);
                    return switch (arg) {
                        .bytes => |value| .{ .bytes = value },
                        else => .{ .invalid = {} },
                    };
                },
            }
        },
    };
}

pub fn validateConstraintExpr(
    comptime expr: []const u8,
    comptime account_name: []const u8,
    accounts: anytype,
) !void {
    const parsed = comptime parseConstraint(expr);
    comptime validateConstraintTypes(parsed, account_name, @TypeOf(accounts));
    const result = evalExpr(parsed, parsed.root, account_name, accounts);
    if (result != .bool or !result.bool) {
        return error.ConstraintRaw;
    }
}

/// Constraint specification for account validation
///
/// Used to define validation rules for accounts in an instruction context.
/// Each field corresponds to an Anchor constraint attribute.
///
/// Example:
/// ```zig
/// const my_constraints = Constraints{
///     .mut = true,
///     .signer = true,
///     .owner = my_program_id,
/// };
/// ```
pub const Constraints = struct {
    /// Account must be mutable (writable)
    ///
    /// Anchor equivalent: `#[account(mut)]`
    mut: bool = false,

    /// Account must be a signer of the transaction
    ///
    /// Anchor equivalent: `#[account(signer)]`
    signer: bool = false,

    /// Account must be owned by specified program
    ///
    /// Anchor equivalent: `#[account(owner = <program>)]`
    owner: ?PublicKey = null,

    /// Account must have exact public key address
    ///
    /// Anchor equivalent: `#[account(address = <pubkey>)]`
    address: ?PublicKey = null,

    /// Account must be executable (for program accounts)
    ///
    /// Anchor equivalent: `#[account(executable)]`
    executable: bool = false,

    // Note: rent_exempt constraint is planned for future phases.
    // It requires access to the Rent sysvar for proper validation.
};

/// Validate constraints against an account
///
/// Checks all specified constraints and returns the first violation found.
/// Returns null if all constraints pass.
///
/// Example:
/// ```zig
/// const constraints = Constraints{ .mut = true, .signer = true };
/// if (validateConstraints(&account_info, constraints)) |err| {
///     return err;
/// }
/// ```
pub fn validateConstraints(info: *const Account.Info, constraints: Constraints) ?AnchorError {
    // Check mut constraint
    if (constraints.mut and info.is_writable == 0) {
        return AnchorError.ConstraintMut;
    }

    // Check signer constraint
    if (constraints.signer and info.is_signer == 0) {
        return AnchorError.ConstraintSigner;
    }

    // Check owner constraint
    if (constraints.owner) |expected_owner| {
        if (!info.owner_id.equals(expected_owner)) {
            return AnchorError.ConstraintOwner;
        }
    }

    // Check address constraint
    if (constraints.address) |expected_address| {
        if (!info.id.equals(expected_address)) {
            return AnchorError.ConstraintAddress;
        }
    }

    // Check executable constraint
    if (constraints.executable and info.is_executable == 0) {
        return AnchorError.ConstraintExecutable;
    }

    // All constraints passed
    return null;
}

/// Validate constraints, returning error union for try/catch usage
///
/// Example:
/// ```zig
/// try validateConstraintsOrError(&account_info, constraints);
/// ```
pub fn validateConstraintsOrError(info: *const Account.Info, constraints: Constraints) !void {
    if (validateConstraints(info, constraints)) |err| {
        return switch (err) {
            .ConstraintMut => error.ConstraintMut,
            .ConstraintSigner => error.ConstraintSigner,
            .ConstraintOwner => error.ConstraintOwner,
            .ConstraintAddress => error.ConstraintAddress,
            .ConstraintExecutable => error.ConstraintExecutable,
            else => error.ConstraintRaw,
        };
    }
}

/// Constraint validation errors
pub const ConstraintError = error{
    ConstraintMut,
    ConstraintSigner,
    ConstraintOwner,
    ConstraintAddress,
    ConstraintExecutable,
    ConstraintRaw,
    // Reserved for future phases:
    ConstraintSeeds, // Phase 2: PDA validation
    ConstraintHasOne, // Phase 3: Field validation
    ConstraintRentExempt, // Future: Requires Rent sysvar
};

// ============================================================================
// Tests
// ============================================================================

test "validateConstraints passes with no constraints" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{};
    try std.testing.expect(validateConstraints(&info, constraints) == null);
}

test "validateConstraints fails mut when not writable" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .mut = true };
    try std.testing.expectEqual(AnchorError.ConstraintMut, validateConstraints(&info, constraints).?);
}

test "validateConstraints passes mut when writable" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const constraints = Constraints{ .mut = true };
    try std.testing.expect(validateConstraints(&info, constraints) == null);
}

test "validateConstraints fails signer when not signing" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .signer = true };
    try std.testing.expectEqual(AnchorError.ConstraintSigner, validateConstraints(&info, constraints).?);
}

test "validateConstraints passes signer when signing" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .signer = true };
    try std.testing.expect(validateConstraints(&info, constraints) == null);
}

test "validateConstraints fails owner mismatch" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    // Use TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA (Token Program) - different from default (all zeros)
    const expected_owner = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .owner = expected_owner };
    try std.testing.expectEqual(AnchorError.ConstraintOwner, validateConstraints(&info, constraints).?);
}

test "validateConstraints passes owner match" {
    var id = PublicKey.default();
    // Use Token Program ID for both owner and expected to test matching
    var owner = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .owner = owner };
    try std.testing.expect(validateConstraints(&info, constraints) == null);
}

test "validateConstraints fails address mismatch" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    // Use Token Program ID as expected address - different from default (all zeros)
    const expected_address = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const constraints = Constraints{ .address = expected_address };
    try std.testing.expectEqual(AnchorError.ConstraintAddress, validateConstraints(&info, constraints).?);
}

test "validateConstraints checks multiple constraints" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    const info = Account.Info{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    const constraints = Constraints{
        .mut = true,
        .signer = true,
    };
    try std.testing.expect(validateConstraints(&info, constraints) == null);
}

test "constraint expressions support comparisons and logic" {
    const Accounts = struct {
        a: struct {
            value: i128,
            flag: bool,
        },
        b: i128,
        flag: bool,
        maybe: ?struct {
            value: i128,
        },
    };

    const accounts = Accounts{
        .a = .{ .value = 10, .flag = true },
        .b = 3,
        .flag = true,
        .maybe = null,
    };

    try validateConstraintExpr("a.value > b && flag == true", "a", accounts);
    try validateConstraintExpr("a.value >= b && a.flag == true", "a", accounts);
    try validateConstraintExpr("a.value < 20 || flag == false", "a", accounts);
    try validateConstraintExpr("!(a.value <= b)", "a", accounts);
    try validateConstraintExpr("flag == true || maybe.value > 0", "a", accounts);
    try std.testing.expectError(error.ConstraintRaw, validateConstraintExpr("flag == false && maybe.value > 0", "a", accounts));
    try std.testing.expectError(error.ConstraintRaw, validateConstraintExpr("a.value < b", "a", accounts));
}

test "constraint expressions support arithmetic and helpers" {
    const Accounts = struct {
        a: struct {
            value: i128,
            name: [5]u8,
            label: []const u8,
        },
        b: i128,
    };

    const accounts = Accounts{
        .a = .{
            .value = 10,
            .name = .{ 'a', 'l', 'i', 'c', 'e' },
            .label = "alpha",
        },
        .b = 3,
    };

    try validateConstraintExpr("a.value + b * 2 == 16", "a", accounts);
    try validateConstraintExpr("abs(-a.value) == 10", "a", accounts);
    try validateConstraintExpr("a.value % b == 1", "a", accounts);
    try validateConstraintExpr("len(a.name) == 5", "a", accounts);
    try validateConstraintExpr("starts_with(a.label, \"al\") == true", "a", accounts);
    try validateConstraintExpr("ends_with(a.label, \"ha\")", "a", accounts);
    try validateConstraintExpr("a.label == \"alpha\"", "a", accounts);
    try validateConstraintExpr("contains(a.label, \"lp\")", "a", accounts);
    try validateConstraintExpr("starts_with_ci(a.label, \"AL\")", "a", accounts);
    try validateConstraintExpr("ends_with_ci(a.label, \"HA\")", "a", accounts);
    try validateConstraintExpr("contains_ci(a.label, \"LP\")", "a", accounts);
    try validateConstraintExpr("is_empty(\"\")", "a", accounts);
    try validateConstraintExpr("min(a.value, b) == 3", "a", accounts);
    try validateConstraintExpr("max(a.value, b) == 10", "a", accounts);
    try validateConstraintExpr("clamp(a.value, 0, 7) == 7", "a", accounts);
    try std.testing.expectError(error.ConstraintRaw, validateConstraintExpr("a.value / 0 == 1", "a", accounts));
    try std.testing.expectError(error.ConstraintRaw, validateConstraintExpr("starts_with(a.label, \"zz\")", "a", accounts));
    try std.testing.expectError(error.ConstraintRaw, validateConstraintExpr("starts_with_ci(a.label, \"ZZ\")", "a", accounts));
}

test "constraint typed builder emits valid expressions" {
    const c = constraint_typed;
    const Accounts = struct {
        label: []const u8,
        count: i128,
        authority: PublicKey,
    };

    const accounts = Accounts{
        .label = "ctr",
        .count = 2,
        .authority = PublicKey.comptimeFromBase58("11111111111111111111111111111111"),
    };

    const expr = c.field("label")
        .startsWith("ct")
        .and_(c.field("count").add(c.int_(1)).eq(c.int_(3)));

    try validateConstraintExpr(expr.expr, "label", accounts);

    const key_expr = c.field("authority").eq(c.pubkey("11111111111111111111111111111111"));
    try validateConstraintExpr(key_expr.expr, "authority", accounts);

    const direct_key = c.pubkeyValue(PublicKey.comptimeFromBase58("11111111111111111111111111111111"));
    const direct_expr = c.field("authority").eq(direct_key);
    try validateConstraintExpr(direct_expr.expr, "authority", accounts);

    const direct_expr2 = c.field("authority").eq(c.pubkey(PublicKey.comptimeFromBase58("11111111111111111111111111111111")));
    try validateConstraintExpr(direct_expr2.expr, "authority", accounts);

    const typed_expr = c.field("label").asBytes().len().eq(c.int_(3));
    try validateConstraintExpr(typed_expr.expr, "label", accounts);

    const hex_expr = c.field("label").eq(c.bytesFromHex("637472"));
    try validateConstraintExpr(hex_expr.expr, "label", accounts);
}
