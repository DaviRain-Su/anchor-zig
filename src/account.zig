//! Zig implementation of Anchor Account wrapper
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/account.rs
//!
//! Account<T> is a wrapper that validates discriminators and provides
//! type-safe access to account data. It automatically checks the 8-byte
//! discriminator at the start of account data matches the expected value.
//!
//! ## Example
//! ```zig
//! const Counter = anchor.Account(struct {
//!     count: u64,
//!     authority: PublicKey,
//! }, .{
//!     .discriminator = anchor.accountDiscriminator("Counter"),
//! });
//!
//! // In instruction handler:
//! const counter = try Counter.load(&account_info);
//! counter.data.count += 1;
//! ```

const std = @import("std");
const discriminator_mod = @import("discriminator.zig");
const anchor_error = @import("error.zig");
const constraints_mod = @import("constraints.zig");
const ConstraintExpr = constraints_mod.ConstraintExpr;
const attr_mod = @import("attr.zig");
const Attr = attr_mod.Attr;
const seeds_mod = @import("seeds.zig");
const init_mod = @import("init.zig");
const pda_mod = @import("pda.zig");
const has_one_mod = @import("has_one.zig");
const realloc_mod = @import("realloc.zig");
const program_mod = @import("program.zig");
const sol = @import("solana_program_sdk");

// Import from parent SDK
const sdk_account = sol.account;
const PublicKey = sol.PublicKey;
const UncheckedProgram = program_mod.UncheckedProgram;

const Discriminator = discriminator_mod.Discriminator;
const DISCRIMINATOR_LENGTH = discriminator_mod.DISCRIMINATOR_LENGTH;
const AnchorError = anchor_error.AnchorError;
const Constraints = constraints_mod.Constraints;
const AccountInfo = sdk_account.Account.Info;
const SeedSpec = seeds_mod.SeedSpec;
const PdaError = pda_mod.PdaError;
const HasOneSpec = has_one_mod.HasOneSpec;
const ReallocConfig = realloc_mod.ReallocConfig;

fn fieldTypeByName(comptime T: type, comptime name: []const u8) ?type {
    const info = @typeInfo(T);
    if (info != .@"struct") {
        @compileError("expected struct for account data type");
    }
    inline for (info.@"struct".fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return field.type;
        }
    }
    return null;
}

fn isHasOneFieldType(comptime FieldType: type) bool {
    if (FieldType == PublicKey or FieldType == [32]u8) return true;
    if (@typeInfo(FieldType) == .pointer) {
        return @typeInfo(FieldType).pointer.child == PublicKey;
    }
    return false;
}

fn isSeedFieldType(comptime FieldType: type) bool {
    if (FieldType == PublicKey) return true;
    if (@typeInfo(FieldType) == .array) {
        const array = @typeInfo(FieldType).array;
        return array.child == u8;
    }
    return false;
}

const SpaceParser = struct {
    input: []const u8,
    index: usize,

    fn init(comptime input: []const u8) SpaceParser {
        return .{ .input = input, .index = 0 };
    }

    fn eof(self: *const SpaceParser) bool {
        return self.index >= self.input.len;
    }

    fn peek(self: *const SpaceParser) ?u8 {
        if (self.eof()) return null;
        return self.input[self.index];
    }

    fn skipWs(self: *SpaceParser) void {
        while (self.peek()) |c| {
            if (c != ' ' and c != '\n' and c != '\t' and c != '\r') break;
            self.index += 1;
        }
    }

    fn consumeChar(self: *SpaceParser, comptime expected: u8) bool {
        if (self.peek() == expected) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn parseIdent(self: *SpaceParser) []const u8 {
        const start = self.index;
        while (self.peek()) |c| {
            if (!(std.ascii.isAlphabetic(c) or std.ascii.isDigit(c) or c == '_')) break;
            self.index += 1;
        }
        if (self.index == start) {
            @compileError("space expression parse error: expected identifier");
        }
        return self.input[start..self.index];
    }

    fn parseQualifiedIdent(self: *SpaceParser) []const u8 {
        var last = self.parseIdent();
        while (true) {
            self.skipWs();
            if (!self.consumeChar(':')) break;
            self.expectChar(':');
            self.skipWs();
            last = self.parseIdent();
        }
        return last;
    }

    fn parseInt(self: *SpaceParser) usize {
        const start = self.index;
        while (self.peek()) |c| {
            if (!std.ascii.isDigit(c)) break;
            self.index += 1;
        }
        if (self.index == start) {
            @compileError("space expression parse error: expected integer");
        }
        return std.fmt.parseInt(usize, self.input[start..self.index], 10) catch {
            @compileError("space expression parse error: invalid integer");
        };
    }

    fn expectChar(self: *SpaceParser, comptime expected: u8) void {
        if (!self.consumeChar(expected)) {
            @compileError("space expression parse error: expected character");
        }
    }

    fn expectEof(self: *SpaceParser) void {
        if (!self.eof()) {
            @compileError("space expression parse error: trailing input");
        }
    }
};

fn resolveSpaceConst(comptime T: type, comptime name: []const u8) usize {
    if (!@hasDecl(T, name)) {
        @compileError("space expression unknown constant: " ++ name);
    }
    const raw = @field(T, name);
    const RawType = @TypeOf(raw);
    if (@typeInfo(RawType) == .comptime_int) {
        return @as(usize, raw);
    }
    if (@typeInfo(RawType) == .int) {
        return @as(usize, @intCast(raw));
    }
    @compileError("space expression constant must be integer: " ++ name);
}

fn resolveSpaceExpr(comptime T: type, comptime expr: []const u8) usize {
    comptime var parser = SpaceParser.init(expr);
    comptime var total: usize = 0;

    parser.skipWs();
    while (true) {
        const value = blk: {
            if (parser.peek()) |c| {
                if (std.ascii.isDigit(c)) {
                    break :blk parser.parseInt();
                }
            }
            const ident = parser.parseQualifiedIdent();
            break :blk resolveSpaceConst(T, ident);
        };
        total += value;
        parser.skipWs();
        if (parser.consumeChar('+')) {
            parser.skipWs();
            continue;
        }
        parser.expectEof();
        break;
    }

    return total;
}

/// Configuration for Account wrapper
pub const AccountConfig = struct {
    /// 8-byte discriminator (required)
    ///
    /// Generate using `accountDiscriminator("AccountName")`
    discriminator: Discriminator,

    /// Expected owner program (optional)
    ///
    /// If specified, account must be owned by this program
    owner: ?PublicKey = null,

    /// Expected owner expression (optional)
    ///
    /// Macro-style expression, evaluated at runtime.
    owner_expr: ?[]const u8 = null,

    /// Account must be mutable (writable)
    mut: bool = false,

    /// Account must be signer
    signer: bool = false,

    /// Account data must be zeroed
    ///
    /// Anchor equivalent: `#[account(zero)]`
    zero: bool = false,

    /// Account can be duplicated
    ///
    /// Anchor equivalent: `#[account(dup)]`
    dup: bool = false,

    /// Expected address (optional)
    address: ?PublicKey = null,

    /// Expected address expression (optional)
    ///
    /// Macro-style expression, evaluated at runtime.
    address_expr: ?[]const u8 = null,

    /// Account must be executable
    executable: bool = false,

    /// Required space override (optional)
    ///
    /// If not specified, calculated as DISCRIMINATOR_LENGTH + @sizeOf(T)
    space: ?usize = null,

    /// Required space expression (optional)
    ///
    /// Macro-style expression, evaluated at comptime.
    space_expr: ?[]const u8 = null,

    // === Phase 2: PDA Support ===

    /// PDA seeds specification (optional)
    ///
    /// Specify seeds for PDA validation during account loading.
    /// Example: `.seeds = &.{ anchor.seed("counter"), anchor.seedAccount("authority") }`
    seeds: ?[]const SeedSpec = null,

    /// Store bump seed in account data (optional)
    ///
    /// When true, the bump seed will be stored and validated.
    /// Requires seeds to be specified.
    bump: bool = false,

    /// Bump seed field name (optional)
    ///
    /// Anchor equivalent: `bump = <field>`
    /// Requires seeds to be specified.
    bump_field: ?[]const u8 = null,

    /// Program seed override (optional)
    ///
    /// Anchor equivalent: `seeds::program = <expr>`
    /// Requires seeds to be specified and cannot be used with init.
    seeds_program: ?SeedSpec = null,

    /// Initialize if needed (optional)
    ///
    /// Anchor equivalent: `init_if_needed`
    /// Requires payer field to be specified.
    init_if_needed: bool = false,

    /// Initialize new account (optional)
    ///
    /// When true, the account will be created if it doesn't exist.
    /// Requires payer field to be specified.
    init: bool = false,

    /// Payer account field name (for init)
    ///
    /// Required when init is true. References a field in the Accounts struct
    /// that will pay for account creation.
    payer: ?[]const u8 = null,

    // === Phase 3: Advanced Constraints ===

    /// has_one constraints - validate field matches account key
    ///
    /// Validates that a PublicKey field in account data matches another
    /// account's public key from the Accounts struct.
    ///
    /// Example:
    /// ```zig
    /// .has_one = &.{
    ///     .{ .field = "authority", .target = "authority" },
    ///     .{ .field = "mint", .target = "mint" },
    /// }
    /// ```
    has_one: ?[]const HasOneSpec = null,

    /// Associated token constraints (optional)
    ///
    /// Anchor equivalent: `associated_token::mint/authority`
    associated_token: ?AssociatedTokenConfig = null,

    /// Token account mint constraint (optional)
    ///
    /// Anchor equivalent: `token::mint`
    token_mint: ?[]const u8 = null,

    /// Token account authority constraint (optional)
    ///
    /// Anchor equivalent: `token::authority`
    token_authority: ?[]const u8 = null,

    /// Token program constraint (optional)
    ///
    /// Anchor equivalent: `token::token_program`
    token_program: ?[]const u8 = null,

    /// Mint authority constraint (optional)
    ///
    /// Anchor equivalent: `mint::authority`
    mint_authority: ?[]const u8 = null,

    /// Mint freeze authority constraint (optional)
    ///
    /// Anchor equivalent: `mint::freeze_authority`
    mint_freeze_authority: ?[]const u8 = null,

    /// Mint decimals constraint (optional)
    ///
    /// Anchor equivalent: `mint::decimals`
    mint_decimals: ?u8 = null,

    /// Mint token program constraint (optional)
    ///
    /// Anchor equivalent: `mint::token_program`
    mint_token_program: ?[]const u8 = null,

    /// Close destination account field name
    ///
    /// When specified, the account can be closed by transferring all
    /// lamports to the named destination account and zeroing data.
    ///
    /// Example: `.close = "destination"`
    close: ?[]const u8 = null,

    /// Realloc configuration for dynamic account resizing
    ///
    /// Enables dynamic resizing of account data. The payer will pay
    /// for additional rent when growing, and receive refunds when shrinking.
    ///
    /// Example:
    /// ```zig
    /// .realloc = .{
    ///     .payer = "payer",
    ///     .zero_init = true,
    /// }
    /// ```
    realloc: ?ReallocConfig = null,

    /// Rent-exempt constraint hint (not validated yet)
    ///
    /// Anchor equivalent: `#[account(rent_exempt)]`
    rent_exempt: bool = false,

    /// Custom constraint expression (IDL only)
    ///
    /// Anchor equivalent: `#[account(constraint = <expr>)]`
    constraint: ?ConstraintExpr = null,

    /// Attribute DSL list (optional)
    attrs: ?[]const Attr = null,
};

pub const AssociatedTokenConfig = struct {
    mint: []const u8,
    authority: []const u8,
    token_program: ?[]const u8 = null,
};

/// Account wrapper with additional field-level attrs.
///
/// This helper rebuilds an Account type from an existing Account wrapper
/// and merges extra attrs without touching the original Account config.
pub fn AccountField(comptime Base: type, comptime attrs: []const Attr) type {
    if (!@hasDecl(Base, "DataType") or !@hasDecl(Base, "discriminator")) {
        @compileError("AccountField requires an Account wrapper type");
    }

    return Account(Base.DataType, .{
        .discriminator = Base.discriminator,
        .owner = Base.OWNER,
        .owner_expr = Base.OWNER_EXPR,
        .mut = Base.HAS_MUT,
        .signer = Base.HAS_SIGNER,
        .zero = Base.IS_ZERO,
        .dup = Base.IS_DUP,
        .address = Base.ADDRESS,
        .address_expr = Base.ADDRESS_EXPR,
        .executable = Base.EXECUTABLE,
        .space = Base.SPACE,
        .space_expr = Base.SPACE_EXPR,
        .seeds = Base.SEEDS,
        .bump = Base.HAS_BUMP,
        .bump_field = Base.BUMP_FIELD,
        .seeds_program = Base.SEEDS_PROGRAM,
        .init = Base.IS_INIT,
        .init_if_needed = Base.IS_INIT_IF_NEEDED,
        .payer = Base.PAYER,
        .has_one = Base.HAS_ONE,
        .associated_token = Base.ASSOCIATED_TOKEN,
        .token_mint = Base.TOKEN_MINT,
        .token_authority = Base.TOKEN_AUTHORITY,
        .token_program = Base.TOKEN_PROGRAM,
        .mint_authority = Base.MINT_AUTHORITY,
        .mint_freeze_authority = Base.MINT_FREEZE_AUTHORITY,
        .mint_decimals = Base.MINT_DECIMALS,
        .mint_token_program = Base.MINT_TOKEN_PROGRAM,
        .close = Base.CLOSE,
        .realloc = Base.REALLOC,
        .rent_exempt = Base.RENT_EXEMPT,
        .constraint = Base.CONSTRAINT,
        .attrs = attrs,
    });
}

fn applyAttrs(comptime base: AccountConfig, comptime attrs: []const Attr) AccountConfig {
    comptime var result = base;
    comptime var space_config_set = false;

    inline for (attrs) |attr| {
        switch (attr) {
            .mut => {
                if (result.mut) @compileError("mut already set");
                result.mut = true;
            },
            .signer => {
                if (result.signer) @compileError("signer already set");
                result.signer = true;
            },
            .zero => {
                if (result.zero) @compileError("zero already set");
                result.zero = true;
            },
            .dup => {
                if (result.dup) @compileError("dup already set");
                result.dup = true;
            },
            .seeds => |value| {
                if (result.seeds != null) @compileError("seeds already set");
                result.seeds = value;
            },
            .bump => {
                if (result.bump) @compileError("bump already set");
                result.bump = true;
            },
            .bump_field => |value| {
                if (result.bump_field != null) @compileError("bump field already set");
                result.bump_field = value;
                result.bump = true;
            },
            .seeds_program => |value| {
                if (result.seeds_program != null) @compileError("seeds::program already set");
                result.seeds_program = value;
            },
            .init_if_needed => {
                if (result.init_if_needed) @compileError("init_if_needed already set");
                if (result.init) @compileError("init_if_needed cannot be used with init");
                result.init_if_needed = true;
                result.init = true;
            },
            .init => {
                if (result.init) @compileError("init already set");
                result.init = true;
            },
            .payer => |value| {
                if (result.payer != null) @compileError("payer already set");
                result.payer = value;
            },
            .close => |value| {
                if (result.close != null) @compileError("close already set");
                result.close = value;
            },
            .realloc => |value| {
                if (result.realloc != null) @compileError("realloc already set");
                result.realloc = value;
            },
            .has_one => |value| {
                if (result.has_one != null) @compileError("has_one already set");
                result.has_one = value;
            },
            .associated_token_mint => |value| {
                if (result.associated_token != null and result.associated_token.?.mint.len != 0) {
                    @compileError("associated_token mint already set");
                }
                const authority = if (result.associated_token) |cfg| cfg.authority else "";
                const token_program = if (result.associated_token) |cfg| cfg.token_program else null;
                result.associated_token = .{
                    .mint = value,
                    .authority = authority,
                    .token_program = token_program,
                };
            },
            .associated_token_authority => |value| {
                if (result.associated_token != null and result.associated_token.?.authority.len != 0) {
                    @compileError("associated_token authority already set");
                }
                const mint = if (result.associated_token) |cfg| cfg.mint else "";
                const token_program = if (result.associated_token) |cfg| cfg.token_program else null;
                result.associated_token = .{
                    .mint = mint,
                    .authority = value,
                    .token_program = token_program,
                };
            },
            .associated_token_token_program => |value| {
                if (result.associated_token != null and result.associated_token.?.token_program != null) {
                    @compileError("associated_token token_program already set");
                }
                const mint = if (result.associated_token) |cfg| cfg.mint else "";
                const authority = if (result.associated_token) |cfg| cfg.authority else "";
                result.associated_token = .{
                    .mint = mint,
                    .authority = authority,
                    .token_program = value,
                };
            },
            .token_mint => |value| {
                if (result.token_mint != null) @compileError("token::mint already set");
                result.token_mint = value;
            },
            .token_authority => |value| {
                if (result.token_authority != null) @compileError("token::authority already set");
                result.token_authority = value;
            },
            .token_program => |value| {
                if (result.token_program != null) @compileError("token::token_program already set");
                result.token_program = value;
            },
            .mint_authority => |value| {
                if (result.mint_authority != null) @compileError("mint::authority already set");
                result.mint_authority = value;
            },
            .mint_freeze_authority => |value| {
                if (result.mint_freeze_authority != null) {
                    @compileError("mint::freeze_authority already set");
                }
                result.mint_freeze_authority = value;
            },
            .mint_decimals => |value| {
                if (result.mint_decimals != null) @compileError("mint::decimals already set");
                result.mint_decimals = value;
            },
            .mint_token_program => |value| {
                if (result.mint_token_program != null) @compileError("mint::token_program already set");
                result.mint_token_program = value;
            },
            .rent_exempt => {
                if (result.rent_exempt) @compileError("rent_exempt already set");
                result.rent_exempt = true;
            },
            .constraint => |value| {
                if (result.constraint != null) @compileError("constraint already set");
                result.constraint = value;
            },
            .owner => |value| {
                if (result.owner != null) @compileError("owner already set");
                result.owner = value;
            },
            .owner_expr => |value| {
                if (result.owner_expr != null or result.owner != null) {
                    @compileError("owner already set");
                }
                result.owner_expr = value;
            },
            .address => |value| {
                if (result.address != null) @compileError("address already set");
                result.address = value;
            },
            .address_expr => |value| {
                if (result.address_expr != null or result.address != null) {
                    @compileError("address already set");
                }
                result.address_expr = value;
            },
            .executable => {
                if (result.executable) @compileError("executable already set");
                result.executable = true;
            },
            .space => |value| {
                if (space_config_set) @compileError("space already set");
                space_config_set = true;
                result.space = value;
                result.space_expr = null;
            },
            .space_expr => |value| {
                if (space_config_set) @compileError("space already set");
                space_config_set = true;
                result.space = null;
                result.space_expr = value;
            },
        }
    }

    return result;
}

/// Account wrapper with discriminator validation
///
/// Provides type-safe access to account data with automatic
/// discriminator verification on load.
///
/// Type Parameters:
/// - `T`: The account data struct type
/// - `config`: AccountConfig with discriminator and optional constraints
///
/// Example:
/// ```zig
/// const Counter = anchor.Account(struct {
///     count: u64,
///     authority: PublicKey,
/// }, .{ .discriminator = anchor.accountDiscriminator("Counter") });
/// ```
pub fn Account(comptime T: type, comptime config: AccountConfig) type {
    // Merge attribute DSL if provided
    comptime var merged = config;
    if (merged.attrs) |attrs| {
        merged = applyAttrs(merged, attrs);
    }
    merged.attrs = null;
    if (merged.space_expr != null and merged.space != null) {
        @compileError("space and space_expr are mutually exclusive");
    }
    if (merged.space_expr) |expr| {
        merged.space = resolveSpaceExpr(T, expr);
    }

    // Validate config at compile time
    comptime {
        if (merged.bump and merged.seeds == null) {
            @compileError("bump requires seeds to be specified");
        }
        if (merged.bump_field != null and merged.seeds == null) {
            @compileError("bump field requires seeds to be specified");
        }
        if (merged.seeds_program != null and merged.seeds == null) {
            @compileError("seeds::program requires seeds to be specified");
        }
        if (merged.seeds_program != null and merged.init) {
            @compileError("seeds::program cannot be used with init");
        }
        if (merged.init_if_needed and merged.payer == null) {
            @compileError("init_if_needed requires payer to be specified");
        }
        if (merged.init and merged.payer == null) {
            @compileError("init requires payer to be specified");
        }
        if (merged.seeds) |s| {
            seeds_mod.validateSeeds(s);
            for (s) |seed| {
                switch (seed) {
                    .field => |name| {
                        const FieldType = fieldTypeByName(T, name) orelse {
                            @compileError("seed field not found in account data: " ++ name);
                        };
                        if (!isSeedFieldType(FieldType)) {
                            @compileError("seed field must be PublicKey or [N]u8");
                        }
                    },
                    else => {},
                }
            }
        }
        if (merged.bump_field) |name| {
            const FieldType = fieldTypeByName(T, name) orelse {
                @compileError("bump field not found in account data: " ++ name);
            };
            if (FieldType != u8) {
                @compileError("bump field must be u8");
            }
        }
        if (merged.has_one) |list| {
            for (list) |spec| {
                const FieldType = fieldTypeByName(T, spec.field) orelse {
                    @compileError("has_one field not found in account data: " ++ spec.field);
                };
                if (!isHasOneFieldType(FieldType)) {
                    @compileError("has_one field must be PublicKey, [32]u8, or *const PublicKey");
                }
            }
        }
        if (merged.associated_token) |cfg| {
            if (cfg.mint.len == 0 or cfg.authority.len == 0) {
                @compileError("associated_token requires mint and authority");
            }
            if (merged.seeds != null) {
                @compileError("associated_token cannot be used with seeds");
            }
            if (merged.token_mint != null or merged.token_authority != null or merged.token_program != null) {
                @compileError("associated_token cannot be combined with token constraints");
            }
            if (merged.mint_authority != null or
                merged.mint_freeze_authority != null or
                merged.mint_decimals != null or
                merged.mint_token_program != null)
            {
                @compileError("associated_token cannot be combined with mint constraints");
            }
        }
        if ((merged.token_mint != null or merged.token_authority != null or merged.token_program != null) and
            (merged.mint_authority != null or
            merged.mint_freeze_authority != null or
            merged.mint_decimals != null or
            merged.mint_token_program != null))
        {
            @compileError("token constraints cannot be combined with mint constraints");
        }
        if (merged.owner != null and merged.owner_expr != null) {
            @compileError("owner and owner_expr are mutually exclusive");
        }
        if (merged.address != null and merged.address_expr != null) {
            @compileError("address and address_expr are mutually exclusive");
        }
        if (merged.executable) {
            if (merged.mut) {
                @compileError("executable accounts cannot be mutable");
            }
            if (merged.signer) {
                @compileError("executable accounts cannot be signers");
            }
            if (merged.init or merged.init_if_needed) {
                @compileError("executable accounts cannot be initialized");
            }
            if (merged.close != null or merged.realloc != null) {
                @compileError("executable accounts cannot be closed or reallocated");
            }
        }
    }

    return struct {
        const Self = @This();

        /// The discriminator for this account type
        pub const discriminator: Discriminator = merged.discriminator;

        /// Required space: discriminator + data
        pub const SPACE: usize = merged.space orelse (DISCRIMINATOR_LENGTH + @sizeOf(T));

        /// Space expression (if any)
        pub const SPACE_EXPR: ?[]const u8 = merged.space_expr;

        /// Whether space was explicitly configured
        pub const HAS_SPACE_CONSTRAINT: bool = merged.space != null or merged.space_expr != null;

        /// The inner data type
        pub const DataType = T;

        /// Whether this account type has PDA seeds
        pub const HAS_SEEDS: bool = merged.seeds != null;

        /// Whether this account stores a bump seed
        pub const HAS_BUMP: bool = merged.bump or merged.bump_field != null;

        /// Whether this account requires initialization
        pub const IS_INIT: bool = merged.init;

        /// Whether this account uses init_if_needed
        pub const IS_INIT_IF_NEEDED: bool = merged.init_if_needed;

        /// Whether this account must be writable
        pub const HAS_MUT: bool = merged.mut;

        /// Whether this account must be signer
        pub const HAS_SIGNER: bool = merged.signer;

        /// Whether this account is zeroed
        pub const IS_ZERO: bool = merged.zero;

        /// Whether this account is marked as duplicate
        pub const IS_DUP: bool = merged.dup;

        /// The seeds specification (if any)
        pub const SEEDS: ?[]const SeedSpec = merged.seeds;

        /// The bump field name (if any)
        pub const BUMP_FIELD: ?[]const u8 = merged.bump_field;

        /// The program seed override (if any)
        pub const SEEDS_PROGRAM: ?SeedSpec = merged.seeds_program;

        /// The payer field name (if init is required)
        pub const PAYER: ?[]const u8 = merged.payer;

        // === Phase 3 constants ===

        /// Whether this account has has_one constraints
        pub const HAS_HAS_ONE: bool = merged.has_one != null;

        /// Whether this account has close constraint
        pub const HAS_CLOSE: bool = merged.close != null;

        /// Whether this account has realloc constraint
        pub const HAS_REALLOC: bool = merged.realloc != null;

        /// The has_one constraint specifications (if any)
        pub const HAS_ONE: ?[]const HasOneSpec = merged.has_one;

        /// Associated token config (if any)
        pub const ASSOCIATED_TOKEN: ?AssociatedTokenConfig = merged.associated_token;

        /// Token mint constraint (if any)
        pub const TOKEN_MINT: ?[]const u8 = merged.token_mint;

        /// Token authority constraint (if any)
        pub const TOKEN_AUTHORITY: ?[]const u8 = merged.token_authority;

        /// Token program constraint (if any)
        pub const TOKEN_PROGRAM: ?[]const u8 = merged.token_program;

        /// Mint authority constraint (if any)
        pub const MINT_AUTHORITY: ?[]const u8 = merged.mint_authority;

        /// Mint freeze authority constraint (if any)
        pub const MINT_FREEZE_AUTHORITY: ?[]const u8 = merged.mint_freeze_authority;

        /// Mint decimals constraint (if any)
        pub const MINT_DECIMALS: ?u8 = merged.mint_decimals;

        /// Mint token program constraint (if any)
        pub const MINT_TOKEN_PROGRAM: ?[]const u8 = merged.mint_token_program;

        /// The close destination field name (if any)
        pub const CLOSE: ?[]const u8 = merged.close;

        /// The realloc configuration (if any)
        pub const REALLOC: ?ReallocConfig = merged.realloc;

        /// Whether rent-exempt constraint is requested
        pub const RENT_EXEMPT: bool = merged.rent_exempt;

        /// Constraint expression (if any)
        pub const CONSTRAINT: ?ConstraintExpr = merged.constraint;

        /// Expected owner (if any)
        pub const OWNER: ?PublicKey = merged.owner;

        /// Expected owner expression (if any)
        pub const OWNER_EXPR: ?[]const u8 = merged.owner_expr;

        /// Expected address (if any)
        pub const ADDRESS: ?PublicKey = merged.address;

        /// Expected address expression (if any)
        pub const ADDRESS_EXPR: ?[]const u8 = merged.address_expr;

        /// Whether account must be executable
        pub const EXECUTABLE: bool = merged.executable;

        /// The account info from runtime
        info: *const AccountInfo,

        /// Typed access to account data (after discriminator)
        data: *T,

        /// Load and validate an account from AccountInfo
        ///
        /// Validates:
        /// - Account size is sufficient
        /// - Discriminator matches expected value (using fast u64 comparison)
        /// - Owner matches (if specified in config)
        ///
        /// Returns error if validation fails.
        pub fn load(info: *const AccountInfo) !Self {
            // Check minimum size
            if (info.data_len < SPACE) {
                return error.AccountDiscriminatorNotFound;
            }

            if (IS_ZERO) {
                // Zero check: discriminator must be all zeros
                if (!discriminator_mod.isDiscriminatorZero(info.data)) {
                    return error.ConstraintZero;
                }
            } else {
                // Fast discriminator validation using u64 comparison (~5x faster)
                if (!discriminator_mod.validateDiscriminatorFast(info.data, &discriminator)) {
                    return error.AccountDiscriminatorMismatch;
                }
            }

            // Validate owner constraint if specified
            if (merged.owner) |expected_owner| {
                if (!info.owner_id.equals(expected_owner)) {
                    return error.ConstraintOwner;
                }
            }

            // Validate mut constraint if specified
            if (merged.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }

            // Validate signer constraint if specified
            if (merged.signer and info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            // Validate address constraint if specified
            if (merged.address) |expected_address| {
                if (!info.id.equals(expected_address)) {
                    return error.ConstraintAddress;
                }
            }

            // Validate executable constraint if specified
            if (merged.executable and info.is_executable == 0) {
                return error.ConstraintExecutable;
            }

            // Get typed pointer to data (after discriminator)
            const data_ptr: *T = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));

            return Self{
                .info = info,
                .data = data_ptr,
            };
        }

        /// Load account without discriminator validation
        ///
        /// Use with caution - only for accounts where discriminator
        /// validation is handled elsewhere.
        pub fn loadUnchecked(info: *const AccountInfo) !Self {
            if (info.data_len < SPACE) {
                return error.AccountDiscriminatorNotFound;
            }

            const data_ptr: *T = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));

            return Self{
                .info = info,
                .data = data_ptr,
            };
        }

        /// Result of loading an account with PDA validation
        pub const LoadPdaResult = struct {
            account: Self,
            bump: u8,
        };

        /// Load and validate an account with PDA constraint
        ///
        /// Validates:
        /// - Account address matches expected PDA derived from seeds
        /// - Discriminator matches
        /// - Owner matches (if specified)
        ///
        /// Returns the account and the canonical bump seed.
        ///
        /// Example:
        /// ```zig
        /// const result = try Counter.loadWithPda(
        ///     &counter_info,
        ///     .{ "counter", &authority.bytes },
        ///     &program_id,
        /// );
        /// const counter = result.account;
        /// const bump = result.bump;
        /// ```
        pub fn loadWithPda(
            info: *const AccountInfo,
            seeds: anytype,
            program_id: *const PublicKey,
        ) !LoadPdaResult {
            // First validate PDA - this checks the address matches
            const bump = pda_mod.validatePda(info.id, seeds, program_id) catch {
                return error.ConstraintSeeds;
            };

            // Then do normal load (discriminator, owner checks)
            const account = try load(info);

            return LoadPdaResult{
                .account = account,
                .bump = bump,
            };
        }

        /// Load with PDA validation using known bump
        ///
        /// More efficient when bump is already known (e.g., stored in account data).
        /// Uses createProgramAddress instead of findProgramAddress.
        pub fn loadWithPdaBump(
            info: *const AccountInfo,
            seeds: anytype,
            bump: u8,
            program_id: *const PublicKey,
        ) !Self {
            // Validate PDA with known bump
            pda_mod.validatePdaWithBump(info.id, seeds, bump, program_id) catch {
                return error.ConstraintSeeds;
            };

            // Then do normal load
            return try load(info);
        }

        /// Check if this account type requires PDA validation
        pub fn requiresPdaValidation() bool {
            return HAS_SEEDS;
        }

        /// Check if this account type requires initialization
        pub fn requiresInit() bool {
            return IS_INIT;
        }

        /// Initialize a new account with discriminator
        ///
        /// Writes the discriminator and zero-initializes data.
        /// Use this when creating a new account.
        pub fn init(info: *const AccountInfo) !Self {
            if (info.data_len < SPACE) {
                return error.AccountDiscriminatorNotFound;
            }

            // Check account is writable
            if (info.is_writable == 0) {
                return error.ConstraintMut;
            }

            // Write discriminator
            @memcpy(info.data[0..DISCRIMINATOR_LENGTH], &discriminator);

            // Zero initialize data
            const data_ptr: *T = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));
            data_ptr.* = std.mem.zeroes(T);

            return Self{
                .info = info,
                .data = data_ptr,
            };
        }

        /// Get the public key of this account
        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        /// Get the owner program of this account
        pub fn owner(self: Self) *const PublicKey {
            return self.info.owner_id;
        }

        /// Get the lamports balance
        pub fn lamports(self: Self) u64 {
            return self.info.lamports.*;
        }

        /// Check if account is writable
        pub fn isMut(self: Self) bool {
            return self.info.is_writable != 0;
        }

        /// Check if account is signer
        pub fn isSigner(self: Self) bool {
            return self.info.is_signer != 0;
        }

        /// Check if account is executable
        pub fn isExecutable(self: Self) bool {
            return self.info.is_executable != 0;
        }

        /// Get underlying account info
        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }

        /// Get raw data slice (including discriminator)
        pub fn rawData(self: Self) []u8 {
            return self.info.data[0..self.info.data_len];
        }

        // === Phase 3: Constraint Validation Methods ===

        /// Validate has_one constraints against an accounts struct
        ///
        /// This method checks that each field specified in has_one config
        /// matches the corresponding target account's public key.
        ///
        /// Example:
        /// ```zig
        /// // After loading accounts
        /// try vault.validateHasOneConstraints(accounts);
        /// ```
        pub fn validateHasOneConstraints(self: Self, accounts: anytype) !void {
            if (merged.has_one) |specs| {
                inline for (specs) |spec| {
                    // Get the target account from the accounts struct
                    const target = @field(accounts, spec.target);

                    // Get target's public key
                    const target_key: *const PublicKey = if (@hasDecl(@TypeOf(target), "key"))
                        target.key()
                    else if (@TypeOf(target) == *const AccountInfo)
                        target.id
                    else
                        @compileError("has_one target must have key() method or be AccountInfo");

                    // Validate the field matches
                    try has_one_mod.validateHasOne(T, self.data, spec.field, target_key);
                }
            }
        }

        /// Check if has_one constraints are satisfied (returns bool)
        pub fn checkHasOneConstraints(self: Self, accounts: anytype) bool {
            self.validateHasOneConstraints(accounts) catch return false;
            return true;
        }

        /// Validate init/init_if_needed constraints
        ///
        /// Ensures the account is writable, uninitialized (for init), and payer
        /// is a signer + writable when specified.
        pub fn validateInitConstraint(self: Self, accounts: anytype) !void {
            if (!IS_INIT) return;

            if (IS_INIT_IF_NEEDED) {
                if (!init_mod.isUninitialized(self.info)) {
                    return;
                }
            } else {
                if (!init_mod.isUninitialized(self.info)) {
                    return init_mod.InitError.AccountAlreadyInitialized;
                }
            }

            if (self.info.is_writable == 0) {
                return error.ConstraintMut;
            }

            if (PAYER) |payer_field| {
                const payer = @field(accounts, payer_field);
                const PayerType = @TypeOf(payer);

                const payer_info: *const AccountInfo = blk: {
                    if (@typeInfo(PayerType) == .pointer) {
                        const ChildType = @typeInfo(PayerType).pointer.child;
                        if (ChildType == AccountInfo) {
                            break :blk payer;
                        } else if (@hasDecl(ChildType, "toAccountInfo")) {
                            break :blk payer.toAccountInfo();
                        } else {
                            @compileError("init payer pointer must point to AccountInfo or type with toAccountInfo()");
                        }
                    } else if (@hasDecl(PayerType, "toAccountInfo")) {
                        break :blk payer.toAccountInfo();
                    } else {
                        @compileError("init payer must have toAccountInfo() method or be *const AccountInfo");
                    }
                };

                if (payer_info.is_signer == 0) {
                    return error.ConstraintSigner;
                }
                if (payer_info.is_writable == 0) {
                    return error.ConstraintMut;
                }
            }
        }

        /// Validate close constraint preconditions
        ///
        /// Checks that the close destination account is writable.
        /// Call this before executing a close operation.
        pub fn validateCloseConstraint(self: Self, accounts: anytype) !void {
            if (merged.close) |dest_field| {
                if (self.info.is_writable == 0) {
                    return error.ConstraintMut;
                }
                const dest = @field(accounts, dest_field);

                // Get destination AccountInfo
                const dest_info: *const AccountInfo = if (@hasDecl(@TypeOf(dest), "toAccountInfo"))
                    dest.toAccountInfo()
                else if (@TypeOf(dest) == *const AccountInfo)
                    dest
                else
                    @compileError("close target must have toAccountInfo() method or be AccountInfo");

                // Validate destination is writable
                if (dest_info.is_writable == 0) {
                    return error.ConstraintClose;
                }

                // Validate not closing to self
                if (self.info.id.equals(dest_info.id.*)) {
                    return error.ConstraintClose;
                }
            }
        }

        /// Validate realloc constraint preconditions
        ///
        /// Checks that the payer account is a signer (required for growing).
        pub fn validateReallocConstraint(self: Self, accounts: anytype) !void {
            if (merged.realloc) |realloc_config| {
                if (realloc_config.payer) |payer_field| {
                    const payer = @field(accounts, payer_field);
                    const PayerType = @TypeOf(payer);

                    // Get payer AccountInfo - handle both struct types and pointer types
                    const payer_info: *const AccountInfo = blk: {
                        if (@typeInfo(PayerType) == .pointer) {
                            // It's a pointer - check if it's AccountInfo or has toAccountInfo
                            const ChildType = @typeInfo(PayerType).pointer.child;
                            if (ChildType == AccountInfo) {
                                break :blk payer;
                            } else if (@hasDecl(ChildType, "toAccountInfo")) {
                                break :blk payer.toAccountInfo();
                            } else {
                                @compileError("realloc payer pointer must point to AccountInfo or type with toAccountInfo()");
                            }
                        } else if (@hasDecl(PayerType, "toAccountInfo")) {
                            break :blk payer.toAccountInfo();
                        } else {
                            @compileError("realloc payer must have toAccountInfo() method or be *const AccountInfo");
                        }
                    };

                    // Validate payer is signer (needed for potential growth)
                    if (payer_info.is_signer == 0) {
                        return error.ConstraintRealloc;
                    }

                    // Validate payer is writable (for refunds)
                    if (payer_info.is_writable == 0) {
                        return error.ConstraintRealloc;
                    }
                }

                // Validate account is writable (required for realloc)
                if (self.info.is_writable == 0) {
                    return error.ConstraintRealloc;
                }
            }
        }

        /// Validate all Phase 3 constraints
        ///
        /// Convenience method to validate all configured constraints.
        pub fn validateAllConstraints(self: Self, comptime account_name: []const u8, accounts: anytype) !void {
            const token_state = sol.spl.token.state;
            const associated_token_program_id = comptime sol.PublicKey.comptimeFromBase58(
                "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
            );

            const resolve_key = struct {
                fn get(comptime field_name: []const u8, all_accounts: anytype) *const PublicKey {
                    const target = @field(all_accounts, field_name);
                    const TargetType = @TypeOf(target);
                    if (TargetType == *const AccountInfo) {
                        return target.id;
                    }
                    if (@hasDecl(TargetType, "key")) {
                        return target.key();
                    }
                    if (@typeInfo(TargetType) == .pointer and @hasDecl(@typeInfo(TargetType).pointer.child, "key")) {
                        return target.*.key();
                    }
                    @compileError("constraint target must have key() or be AccountInfo: " ++ field_name);
                }
            }.get;

            try self.validateHasOneConstraints(accounts);
            try self.validateInitConstraint(accounts);
            try self.validateCloseConstraint(accounts);
            try self.validateReallocConstraint(accounts);
            if (HAS_SPACE_CONSTRAINT and self.info.data_len != SPACE) {
                return error.ConstraintSpace;
            }
            if (IS_ZERO) {
                const data_slice = self.info.data[0..DISCRIMINATOR_LENGTH];
                for (data_slice) |byte| {
                    if (byte != 0) {
                        return error.ConstraintZero;
                    }
                }
            }
            const default_token_program = sol.spl.TOKEN_PROGRAM_ID;
            if (ASSOCIATED_TOKEN) |cfg| {
                const authority_key = resolve_key(cfg.authority, accounts).*;
                const mint_key = resolve_key(cfg.mint, accounts).*;
                const token_program_key = if (cfg.token_program) |field_name|
                    resolve_key(field_name, accounts).*
                else
                    default_token_program;
                if (!self.info.owner_id.equals(token_program_key)) {
                    return error.ConstraintOwner;
                }
                const token_slice = blk: {
                    if (self.info.data_len >= DISCRIMINATOR_LENGTH + token_state.Account.SIZE and
                        std.mem.eql(u8, self.info.data[0..DISCRIMINATOR_LENGTH], &discriminator))
                    {
                        break :blk self.info.data[DISCRIMINATOR_LENGTH..self.info.data_len];
                    }
                    break :blk self.info.data[0..self.info.data_len];
                };
                const token_account = token_state.Account.unpackUnchecked(token_slice) catch {
                    return error.ConstraintTokenOwner;
                };
                if (!token_account.owner.equals(authority_key)) {
                    return error.ConstraintTokenOwner;
                }
                if (!token_account.mint.equals(mint_key)) {
                    return error.ConstraintAssociated;
                }
                const seeds = .{ &authority_key.bytes, &token_program_key.bytes, &mint_key.bytes };
                const derived = sol.PublicKey.findProgramAddress(seeds, associated_token_program_id) catch {
                    return error.ConstraintAssociated;
                };
                if (!self.info.id.equals(derived.address)) {
                    return error.ConstraintAssociated;
                }
            }
            const has_token_constraints = TOKEN_MINT != null or TOKEN_AUTHORITY != null;
            if (has_token_constraints) {
                const token_program_key = if (TOKEN_PROGRAM) |field_name|
                    resolve_key(field_name, accounts).*
                else
                    default_token_program;
                if (!self.info.owner_id.equals(token_program_key)) {
                    return error.ConstraintOwner;
                }
                const token_slice = blk: {
                    if (self.info.data_len >= DISCRIMINATOR_LENGTH + token_state.Account.SIZE and
                        std.mem.eql(u8, self.info.data[0..DISCRIMINATOR_LENGTH], &discriminator))
                    {
                        break :blk self.info.data[DISCRIMINATOR_LENGTH..self.info.data_len];
                    }
                    break :blk self.info.data[0..self.info.data_len];
                };
                const token_account = token_state.Account.unpackUnchecked(token_slice) catch {
                    if (TOKEN_MINT != null) return error.ConstraintTokenMint;
                    return error.ConstraintTokenOwner;
                };
                if (TOKEN_MINT) |field_name| {
                    const mint_key = resolve_key(field_name, accounts).*;
                    if (!token_account.mint.equals(mint_key)) {
                        return error.ConstraintTokenMint;
                    }
                }
                if (TOKEN_AUTHORITY) |field_name| {
                    const owner_key = resolve_key(field_name, accounts).*;
                    if (!token_account.owner.equals(owner_key)) {
                        return error.ConstraintTokenOwner;
                    }
                }
            } else if (TOKEN_PROGRAM) |field_name| {
                const token_program_key = resolve_key(field_name, accounts).*;
                if (!self.info.owner_id.equals(token_program_key)) {
                    return error.ConstraintOwner;
                }
            }
            const has_mint_constraints = MINT_AUTHORITY != null or
                MINT_FREEZE_AUTHORITY != null or
                MINT_DECIMALS != null;
            if (has_mint_constraints) {
                const mint_program_key = if (MINT_TOKEN_PROGRAM) |field_name|
                    resolve_key(field_name, accounts).*
                else
                    default_token_program;
                if (!self.info.owner_id.equals(mint_program_key)) {
                    return error.ConstraintOwner;
                }
                const mint_slice = blk: {
                    if (self.info.data_len >= DISCRIMINATOR_LENGTH + token_state.Mint.SIZE and
                        std.mem.eql(u8, self.info.data[0..DISCRIMINATOR_LENGTH], &discriminator))
                    {
                        break :blk self.info.data[DISCRIMINATOR_LENGTH..self.info.data_len];
                    }
                    break :blk self.info.data[0..self.info.data_len];
                };
                const mint_account = token_state.Mint.unpackUnchecked(mint_slice) catch {
                    if (MINT_DECIMALS != null) return error.ConstraintMintDecimals;
                    if (MINT_FREEZE_AUTHORITY != null) return error.ConstraintMintFreezeAuthority;
                    return error.ConstraintMintMintAuthority;
                };
                if (MINT_AUTHORITY) |field_name| {
                    const authority_key = resolve_key(field_name, accounts).*;
                    if (!mint_account.mint_authority.isSome() or
                        !mint_account.mint_authority.unwrap().equals(authority_key))
                    {
                        return error.ConstraintMintMintAuthority;
                    }
                }
                if (MINT_FREEZE_AUTHORITY) |field_name| {
                    const authority_key = resolve_key(field_name, accounts).*;
                    if (!mint_account.freeze_authority.isSome() or
                        !mint_account.freeze_authority.unwrap().equals(authority_key))
                    {
                        return error.ConstraintMintFreezeAuthority;
                    }
                }
                if (MINT_DECIMALS) |expected_decimals| {
                    if (mint_account.decimals != expected_decimals) {
                        return error.ConstraintMintDecimals;
                    }
                }
            } else if (MINT_TOKEN_PROGRAM) |field_name| {
                const mint_program_key = resolve_key(field_name, accounts).*;
                if (!self.info.owner_id.equals(mint_program_key)) {
                    return error.ConstraintOwner;
                }
            }
            if (RENT_EXEMPT) {
                const rent = sol.rent.Rent.getOrDefault();
                if (!rent.isExempt(self.info.lamports.*, self.info.data_len)) {
                    return error.ConstraintRentExempt;
                }
            }
            if (OWNER_EXPR) |expr| {
                const full = comptime std.fmt.comptimePrint("{s}.__owner == {s}", .{ account_name, expr });
                try constraints_mod.validateConstraintExpr(full, account_name, accounts);
            }
            if (ADDRESS_EXPR) |expr| {
                const full = comptime std.fmt.comptimePrint("{s}.key() == {s}", .{ account_name, expr });
                try constraints_mod.validateConstraintExpr(full, account_name, accounts);
            }
            if (CONSTRAINT) |expr| {
                try constraints_mod.validateConstraintExpr(expr.expr, account_name, accounts);
            }
        }

        /// Check if account requires constraint validation
        pub fn requiresConstraintValidation() bool {
            return HAS_HAS_ONE or IS_INIT or HAS_CLOSE or HAS_REALLOC or RENT_EXEMPT or
                IS_ZERO or HAS_SPACE_CONSTRAINT or ASSOCIATED_TOKEN != null or TOKEN_MINT != null or
                TOKEN_AUTHORITY != null or
                TOKEN_PROGRAM != null or MINT_AUTHORITY != null or MINT_FREEZE_AUTHORITY != null or
                MINT_DECIMALS != null or MINT_TOKEN_PROGRAM != null or CONSTRAINT != null or
                OWNER_EXPR != null or ADDRESS_EXPR != null;
        }
    };
}

/// Account load errors
pub const AccountError = error{
    AccountDiscriminatorNotFound,
    AccountDiscriminatorMismatch,
    ConstraintOwner,
    ConstraintMut,
    ConstraintSigner,
    ConstraintAddress,
    ConstraintExecutable,
    // Phase 2: PDA errors
    ConstraintSeeds,
    InvalidPda,
    // Phase 3: Advanced constraint errors
    ConstraintHasOne,
    ConstraintClose,
    ConstraintRealloc,
    ConstraintRentExempt,
    ConstraintZero,
    ConstraintSpace,
    ConstraintTokenMint,
    ConstraintTokenOwner,
    ConstraintMintMintAuthority,
    ConstraintMintFreezeAuthority,
    ConstraintMintDecimals,
};

// ============================================================================
// Tests
// ============================================================================

const TestData = struct {
    value: u64,
    flag: bool,
};

const TestAccount = Account(TestData, .{
    .discriminator = discriminator_mod.accountDiscriminator("TestAccount"),
});

test "Account SPACE calculation" {
    // 8 bytes discriminator + 9 bytes data (u64 + bool)
    try std.testing.expectEqual(@as(usize, 8 + @sizeOf(TestData)), TestAccount.SPACE);
}

test "Account.load validates discriminator" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    // Create properly aligned data buffer with correct discriminator
    // Align to 8 bytes (u64 alignment) for TestData
    var data: [32]u8 align(@alignOf(TestData)) = undefined;
    @memcpy(data[0..8], &TestAccount.discriminator);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const account = try TestAccount.load(&info);
    try std.testing.expectEqual(&id, account.key());
}

test "Account.load rejects wrong discriminator" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    // Create data buffer with wrong discriminator
    var data: [32]u8 = undefined;
    @memset(data[0..8], 0xFF);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(error.AccountDiscriminatorMismatch, TestAccount.load(&info));
}

test "Account.load rejects too small account" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    var data: [4]u8 = undefined; // Too small

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(error.AccountDiscriminatorNotFound, TestAccount.load(&info));
}

test "Account.init writes discriminator" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    // Properly aligned data buffer
    var data: [32]u8 align(@alignOf(TestData)) = undefined;
    @memset(&data, 0);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const account = try TestAccount.init(&info);

    // Check discriminator was written
    try std.testing.expectEqualSlices(u8, &TestAccount.discriminator, data[0..8]);

    // Check data was zero initialized
    try std.testing.expectEqual(@as(u64, 0), account.data.value);
    try std.testing.expectEqual(false, account.data.flag);
}

test "Account.init fails on non-writable" {
    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    var data: [32]u8 = undefined;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0, // Not writable
        .is_executable = 0,
    };

    try std.testing.expectError(error.ConstraintMut, TestAccount.init(&info));
}

test "Account with owner constraint" {
    // Use Token Program ID as expected owner - different from default (all zeros)
    const expected_owner = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

    const OwnedAccount = Account(TestData, .{
        .discriminator = discriminator_mod.accountDiscriminator("OwnedAccount"),
        .owner = expected_owner,
    });

    var id = PublicKey.default();
    var wrong_owner = PublicKey.default(); // Different from expected_owner
    var lamports: u64 = 1000;

    // Properly aligned data buffer
    var data: [32]u8 align(@alignOf(TestData)) = undefined;
    @memcpy(data[0..8], &OwnedAccount.discriminator);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &wrong_owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    try std.testing.expectError(error.ConstraintOwner, OwnedAccount.load(&info));
}

// ============================================================================
// Phase 2: PDA Tests
// ============================================================================

test "Account with seeds has HAS_SEEDS true" {
    const PdaData = struct {
        value: u64,
        bump: u8,
    };

    const PdaAccount = Account(PdaData, .{
        .discriminator = discriminator_mod.accountDiscriminator("PdaAccount"),
        .seeds = &.{
            seeds_mod.seed("counter"),
        },
    });

    try std.testing.expect(PdaAccount.HAS_SEEDS);
    try std.testing.expect(!PdaAccount.HAS_BUMP);
    try std.testing.expect(!PdaAccount.IS_INIT);
}

test "Account without seeds has HAS_SEEDS false" {
    try std.testing.expect(!TestAccount.HAS_SEEDS);
    try std.testing.expect(!TestAccount.HAS_BUMP);
}

test "Account with bump has HAS_BUMP true" {
    const BumpData = struct {
        value: u64,
        bump: u8,
    };

    const BumpAccount = Account(BumpData, .{
        .discriminator = discriminator_mod.accountDiscriminator("BumpAccount"),
        .seeds = &.{
            seeds_mod.seed("counter"),
        },
        .bump = true,
    });

    try std.testing.expect(BumpAccount.HAS_SEEDS);
    try std.testing.expect(BumpAccount.HAS_BUMP);
}

test "Account SEEDS constant is accessible" {
    const SeedData = struct {
        value: u64,
    };

    const SeedAccount = Account(SeedData, .{
        .discriminator = discriminator_mod.accountDiscriminator("SeedAccount"),
        .seeds = &.{
            seeds_mod.seed("prefix"),
            seeds_mod.seedAccount("authority"),
        },
    });

    try std.testing.expect(SeedAccount.SEEDS != null);
    try std.testing.expectEqual(@as(usize, 2), SeedAccount.SEEDS.?.len);
}

test "Account with init has IS_INIT true" {
    const InitData = struct {
        value: u64,
    };

    const InitAccount = Account(InitData, .{
        .discriminator = discriminator_mod.accountDiscriminator("InitAccount"),
        .init = true,
        .payer = "payer",
    });

    try std.testing.expect(InitAccount.IS_INIT);
    try std.testing.expect(std.mem.eql(u8, InitAccount.PAYER.?, "payer"));
}

test "LoadPdaResult struct is accessible" {
    const PdaData = struct {
        value: u64,
    };

    const PdaAccount = Account(PdaData, .{
        .discriminator = discriminator_mod.accountDiscriminator("PdaAccount"),
        .seeds = &.{
            seeds_mod.seed("test"),
        },
    });

    // Verify the LoadPdaResult type exists and has correct fields
    const ResultType = PdaAccount.LoadPdaResult;
    try std.testing.expect(@hasField(ResultType, "account"));
    try std.testing.expect(@hasField(ResultType, "bump"));
}

test "loadWithPda returns error for non-PDA address" {
    const PdaData = struct {
        value: u64,
    };

    const PdaAccount = Account(PdaData, .{
        .discriminator = discriminator_mod.accountDiscriminator("PdaAccount"),
        .seeds = &.{
            seeds_mod.seed("counter"),
        },
    });

    var id = PublicKey.default(); // Not a valid PDA for these seeds
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    var data: [32]u8 align(@alignOf(PdaData)) = undefined;
    @memcpy(data[0..8], &PdaAccount.discriminator);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const program_id = PublicKey.default();
    const seeds = .{"counter"};

    // Should return ConstraintSeeds because address doesn't match PDA
    try std.testing.expectError(error.ConstraintSeeds, PdaAccount.loadWithPda(&info, seeds, &program_id));
}

test "loadWithPdaBump returns error for wrong bump" {
    const PdaData = struct {
        value: u64,
    };

    const PdaAccount = Account(PdaData, .{
        .discriminator = discriminator_mod.accountDiscriminator("PdaAccount"),
        .seeds = &.{
            seeds_mod.seed("counter"),
        },
    });

    var id = PublicKey.default(); // Not a valid PDA for these seeds
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    var data: [32]u8 align(@alignOf(PdaData)) = undefined;
    @memcpy(data[0..8], &PdaAccount.discriminator);

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const program_id = PublicKey.default();
    const seeds = .{"counter"};

    // Should return ConstraintSeeds because address doesn't match PDA with this bump
    try std.testing.expectError(error.ConstraintSeeds, PdaAccount.loadWithPdaBump(&info, seeds, 255, &program_id));
}

test "requiresPdaValidation returns true for accounts with seeds" {
    const PdaData = struct {
        value: u64,
    };

    const PdaAccount = Account(PdaData, .{
        .discriminator = discriminator_mod.accountDiscriminator("PdaAccount"),
        .seeds = &.{
            seeds_mod.seed("counter"),
        },
    });

    try std.testing.expect(PdaAccount.requiresPdaValidation());
    try std.testing.expect(!TestAccount.requiresPdaValidation());
}

test "requiresInit returns true for accounts with init" {
    const InitData = struct {
        value: u64,
    };

    const InitAccount = Account(InitData, .{
        .discriminator = discriminator_mod.accountDiscriminator("InitAccount"),
        .init = true,
        .payer = "payer",
    });

    try std.testing.expect(InitAccount.requiresInit());
    try std.testing.expect(!TestAccount.requiresInit());
}

// ============================================================================
// Phase 3: Advanced Constraints Tests
// ============================================================================

test "Account with has_one has HAS_HAS_ONE true" {
    const VaultData = struct {
        authority: PublicKey,
        balance: u64,
    };

    const Vault = Account(VaultData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Vault"),
        .has_one = &.{
            .{ .field = "authority", .target = "authority" },
        },
    });

    try std.testing.expect(Vault.HAS_HAS_ONE);
    try std.testing.expect(!Vault.HAS_CLOSE);
    try std.testing.expect(!Vault.HAS_REALLOC);
}

test "Account without has_one has HAS_HAS_ONE false" {
    try std.testing.expect(!TestAccount.HAS_HAS_ONE);
}

test "Account HAS_ONE constant is accessible" {
    const VaultData = struct {
        authority: PublicKey,
        mint: PublicKey,
    };

    const Vault = Account(VaultData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Vault"),
        .has_one = &.{
            .{ .field = "authority", .target = "authority" },
            .{ .field = "mint", .target = "token_mint" },
        },
    });

    try std.testing.expect(Vault.HAS_ONE != null);
    try std.testing.expectEqual(@as(usize, 2), Vault.HAS_ONE.?.len);
}

test "Account with close has HAS_CLOSE true" {
    const CloseableData = struct {
        value: u64,
    };

    const Closeable = Account(CloseableData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Closeable"),
        .close = "destination",
    });

    try std.testing.expect(Closeable.HAS_CLOSE);
    try std.testing.expect(std.mem.eql(u8, Closeable.CLOSE.?, "destination"));
}

test "Account without close has HAS_CLOSE false" {
    try std.testing.expect(!TestAccount.HAS_CLOSE);
    try std.testing.expect(TestAccount.CLOSE == null);
}

test "Account with realloc has HAS_REALLOC true" {
    const DynamicData = struct {
        len: u32,
    };

    const Dynamic = Account(DynamicData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Dynamic"),
        .realloc = .{
            .payer = "payer",
            .zero_init = true,
        },
    });

    try std.testing.expect(Dynamic.HAS_REALLOC);
    try std.testing.expect(Dynamic.REALLOC != null);
    try std.testing.expect(std.mem.eql(u8, Dynamic.REALLOC.?.payer.?, "payer"));
    try std.testing.expect(Dynamic.REALLOC.?.zero_init);
}

test "Account without realloc has HAS_REALLOC false" {
    try std.testing.expect(!TestAccount.HAS_REALLOC);
    try std.testing.expect(TestAccount.REALLOC == null);
}

test "Account with all Phase 3 constraints" {
    const FullData = struct {
        authority: PublicKey,
        value: u64,
    };

    const Full = Account(FullData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Full"),
        .has_one = &.{
            .{ .field = "authority", .target = "authority" },
        },
        .close = "destination",
        .realloc = .{
            .payer = "payer",
            .zero_init = false,
        },
    });

    try std.testing.expect(Full.HAS_HAS_ONE);
    try std.testing.expect(Full.HAS_CLOSE);
    try std.testing.expect(Full.HAS_REALLOC);
}

test "Account attributes DSL merges config" {
    const FullData = struct {
        authority: PublicKey,
        value: u64,
    };

    const owner_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const address_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");

    const Full = Account(FullData, .{
        .discriminator = discriminator_mod.accountDiscriminator("FullAttr"),
        .attrs = &.{
            attr_mod.attr.mut(),
            attr_mod.attr.signer(),
            attr_mod.attr.seeds(&.{ seeds_mod.seed("full"), seeds_mod.seedAccount("authority") }),
            attr_mod.attr.bump(),
            attr_mod.attr.init(),
            attr_mod.attr.payer("payer"),
            attr_mod.attr.hasOne(&.{.{ .field = "authority", .target = "authority" }}),
            attr_mod.attr.close("destination"),
            attr_mod.attr.realloc(.{ .payer = "payer", .zero_init = true }),
            attr_mod.attr.rentExempt(),
            attr_mod.attr.constraint("authority.key() == full.authority"),
            attr_mod.attr.owner(owner_key),
            attr_mod.attr.address(address_key),
            attr_mod.attr.space(128),
        },
    });

    try std.testing.expect(Full.HAS_SEEDS);
    try std.testing.expect(Full.HAS_BUMP);
    try std.testing.expect(Full.IS_INIT);
    try std.testing.expect(Full.HAS_MUT);
    try std.testing.expect(Full.HAS_SIGNER);
    try std.testing.expect(Full.PAYER != null);
    try std.testing.expect(Full.HAS_HAS_ONE);
    try std.testing.expect(Full.HAS_CLOSE);
    try std.testing.expect(Full.HAS_REALLOC);
    try std.testing.expect(Full.RENT_EXEMPT);
    try std.testing.expect(Full.CONSTRAINT != null);
    try std.testing.expect(Full.OWNER != null);
    try std.testing.expect(Full.ADDRESS != null);
    try std.testing.expectEqual(@as(usize, 128), Full.SPACE);
}

test "AccountField merges field-level attrs" {
    const Data = struct {
        authority: PublicKey,
        bump: u8,
    };

    const Base = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("BaseField"),
        .seeds = &.{ seeds_mod.seed("base"), seeds_mod.seedField("authority") },
        .bump_field = "bump",
    });

    const Wrapped = AccountField(Base, &.{
        attr_mod.attr.mut(),
        attr_mod.attr.signer(),
    });

    try std.testing.expect(Base.HAS_SEEDS);
    try std.testing.expect(Base.HAS_BUMP);
    try std.testing.expect(!Base.HAS_MUT);
    try std.testing.expect(!Base.HAS_SIGNER);

    try std.testing.expect(Wrapped.HAS_SEEDS);
    try std.testing.expect(Wrapped.HAS_BUMP);
    try std.testing.expect(Wrapped.HAS_MUT);
    try std.testing.expect(Wrapped.HAS_SIGNER);
    try std.testing.expect(Wrapped.BUMP_FIELD != null);
    try std.testing.expect(std.mem.eql(u8, Wrapped.BUMP_FIELD.?, "bump"));
}

test "Account attrs support init_if_needed and token constraints" {
    const Data = struct {
        authority: PublicKey,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenAccount"),
        .attrs = &.{
            attr_mod.attr.initIfNeeded(),
            attr_mod.attr.payer("payer"),
            attr_mod.attr.tokenMint("mint"),
            attr_mod.attr.tokenAuthority("authority"),
        },
    });

    try std.testing.expect(TokenAccount.IS_INIT_IF_NEEDED);
    try std.testing.expect(TokenAccount.PAYER != null);
    try std.testing.expect(TokenAccount.TOKEN_MINT != null);
    try std.testing.expect(TokenAccount.TOKEN_AUTHORITY != null);
}

test "Account attrs support associated token constraints" {
    const Data = struct {
        authority: PublicKey,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenAccountAta"),
        .attrs = &.{
            attr_mod.attr.initIfNeeded(),
            attr_mod.attr.payer("payer"),
            attr_mod.attr.associatedTokenMint("mint"),
            attr_mod.attr.associatedTokenAuthority("authority"),
        },
    });

    try std.testing.expect(TokenAccount.IS_INIT_IF_NEEDED);
    try std.testing.expect(TokenAccount.PAYER != null);
    try std.testing.expect(TokenAccount.ASSOCIATED_TOKEN != null);
    try std.testing.expect(std.mem.eql(u8, TokenAccount.ASSOCIATED_TOKEN.?.mint, "mint"));
    try std.testing.expect(std.mem.eql(u8, TokenAccount.ASSOCIATED_TOKEN.?.authority, "authority"));
}

test "Account token constraints validate at runtime" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenConstraint"),
        .token_mint = "mint",
        .token_authority = "authority",
        .token_program = "token_program",
    });

    const Accounts = struct {
        authority: Signer,
        mint: *const AccountInfo,
        token_program: UncheckedProgram,
        token: TokenAccount,
    };

    const mint_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const authority_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;

    var mint_id = mint_key;
    var authority_id = authority_key;
    var token_program_id = token_program_key;
    var token_id = PublicKey.default();
    var owner = token_program_key;
    var lamports: u64 = 1_000_000;

    var token_buffer: [DISCRIMINATOR_LENGTH + token_state.Account.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&token_buffer, 0);
    @memcpy(token_buffer[0..DISCRIMINATOR_LENGTH], &TokenAccount.discriminator);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mint_key.bytes);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH + 32 .. DISCRIMINATOR_LENGTH + 64], &authority_key.bytes);
    token_buffer[DISCRIMINATOR_LENGTH + token_state.Account.STATE_OFFSET] = 1;

    const token_info = AccountInfo{
        .id = &token_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = token_buffer.len,
        .data = token_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const token_program_info = AccountInfo{
        .id = &token_program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    var accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };

    try accounts.token.validateAllConstraints("token", accounts);

    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &authority_key.bytes);
    accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };
    try std.testing.expectError(error.ConstraintTokenMint, accounts.token.validateAllConstraints("token", accounts));
}

test "Account token constraints enforce default token program owner" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenConstraintDefaultOwner"),
        .token_mint = "mint",
        .token_authority = "authority",
    });

    const Accounts = struct {
        authority: Signer,
        mint: *const AccountInfo,
        token: TokenAccount,
    };

    const mint_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const authority_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");

    var mint_id = mint_key;
    var authority_id = authority_key;
    var token_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var token_buffer: [DISCRIMINATOR_LENGTH + token_state.Account.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&token_buffer, 0);
    @memcpy(token_buffer[0..DISCRIMINATOR_LENGTH], &TokenAccount.discriminator);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mint_key.bytes);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH + 32 .. DISCRIMINATOR_LENGTH + 64], &authority_key.bytes);
    token_buffer[DISCRIMINATOR_LENGTH + token_state.Account.STATE_OFFSET] = 1;

    const token_info = AccountInfo{
        .id = &token_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = token_buffer.len,
        .data = token_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token = try TokenAccount.load(&token_info),
    };

    try std.testing.expectError(error.ConstraintOwner, accounts.token.validateAllConstraints("token", accounts));
}

test "Account token program constraint checks owner only" {
    const Data = struct {};

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenProgramOnly"),
        .token_program = "token_program",
    });

    const Accounts = struct {
        token_program: UncheckedProgram,
        token: TokenAccount,
    };

    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;
    var token_program_id = token_program_key;
    var token_id = PublicKey.default();
    var owner = token_program_key;
    var lamports: u64 = 1;

    var token_buffer: [DISCRIMINATOR_LENGTH]u8 align(@alignOf(Data)) = undefined;
    @memset(&token_buffer, 0);
    @memcpy(token_buffer[0..DISCRIMINATOR_LENGTH], &TokenAccount.discriminator);

    const token_info = AccountInfo{
        .id = &token_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = token_buffer.len,
        .data = token_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const token_program_info = AccountInfo{
        .id = &token_program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    var accounts = Accounts{
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };

    try accounts.token.validateAllConstraints("token", accounts);

    owner = PublicKey.default();
    accounts = Accounts{
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };
    try std.testing.expectError(error.ConstraintOwner, accounts.token.validateAllConstraints("token", accounts));
}

test "Account mint constraints validate at runtime" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const MintAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("MintConstraint"),
        .mint_authority = "mint_authority",
        .mint_freeze_authority = "freeze_authority",
        .mint_decimals = 6,
        .mint_token_program = "token_program",
    });

    const Accounts = struct {
        mint_authority: Signer,
        freeze_authority: Signer,
        token_program: UncheckedProgram,
        mint: MintAccount,
    };

    const authority_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const freeze_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;

    var authority_id = authority_key;
    var freeze_id = freeze_key;
    var token_program_id = token_program_key;
    var mint_id = PublicKey.default();
    var owner = token_program_key;
    var lamports: u64 = 1_000_000;

    var mint_buffer: [DISCRIMINATOR_LENGTH + token_state.Mint.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&mint_buffer, 0);
    @memcpy(mint_buffer[0..DISCRIMINATOR_LENGTH], &MintAccount.discriminator);
    std.mem.writeInt(u32, mint_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 4], 1, .little);
    @memcpy(mint_buffer[DISCRIMINATOR_LENGTH + 4 .. DISCRIMINATOR_LENGTH + 36], &authority_key.bytes);
    mint_buffer[DISCRIMINATOR_LENGTH + 44] = 6;
    mint_buffer[DISCRIMINATOR_LENGTH + 45] = 1;
    std.mem.writeInt(u32, mint_buffer[DISCRIMINATOR_LENGTH + 46 .. DISCRIMINATOR_LENGTH + 50], 1, .little);
    @memcpy(mint_buffer[DISCRIMINATOR_LENGTH + 50 .. DISCRIMINATOR_LENGTH + 82], &freeze_key.bytes);

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = mint_buffer.len,
        .data = mint_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const freeze_info = AccountInfo{
        .id = &freeze_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const token_program_info = AccountInfo{
        .id = &token_program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    var accounts = Accounts{
        .mint_authority = try Signer.load(&authority_info),
        .freeze_authority = try Signer.load(&freeze_info),
        .token_program = try UncheckedProgram.load(&token_program_info),
        .mint = try MintAccount.load(&mint_info),
    };

    try accounts.mint.validateAllConstraints("mint", accounts);

    mint_buffer[DISCRIMINATOR_LENGTH + 44] = 9;
    accounts = Accounts{
        .mint_authority = try Signer.load(&authority_info),
        .freeze_authority = try Signer.load(&freeze_info),
        .token_program = try UncheckedProgram.load(&token_program_info),
        .mint = try MintAccount.load(&mint_info),
    };
    try std.testing.expectError(error.ConstraintMintDecimals, accounts.mint.validateAllConstraints("mint", accounts));
}

test "Account mint constraints enforce default token program owner" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const MintAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("MintConstraintDefaultOwner"),
        .mint_authority = "mint_authority",
        .mint_decimals = 6,
    });

    const Accounts = struct {
        mint_authority: Signer,
        mint: MintAccount,
    };

    const authority_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");

    var authority_id = authority_key;
    var mint_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var mint_buffer: [DISCRIMINATOR_LENGTH + token_state.Mint.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&mint_buffer, 0);
    @memcpy(mint_buffer[0..DISCRIMINATOR_LENGTH], &MintAccount.discriminator);
    std.mem.writeInt(u32, mint_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 4], 1, .little);
    @memcpy(mint_buffer[DISCRIMINATOR_LENGTH + 4 .. DISCRIMINATOR_LENGTH + 36], &authority_key.bytes);
    mint_buffer[DISCRIMINATOR_LENGTH + 44] = 6;
    mint_buffer[DISCRIMINATOR_LENGTH + 45] = 1;

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = mint_buffer.len,
        .data = mint_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const accounts = Accounts{
        .mint_authority = try Signer.load(&authority_info),
        .mint = try MintAccount.load(&mint_info),
    };

    try std.testing.expectError(error.ConstraintOwner, accounts.mint.validateAllConstraints("mint", accounts));
}

test "Account mint program constraint checks owner only" {
    const Data = struct {};

    const MintAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("MintProgramOnly"),
        .mint_token_program = "token_program",
    });

    const Accounts = struct {
        token_program: UncheckedProgram,
        mint: MintAccount,
    };

    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;
    var token_program_id = token_program_key;
    var mint_id = PublicKey.default();
    var owner = token_program_key;
    var lamports: u64 = 1;

    var mint_buffer: [DISCRIMINATOR_LENGTH]u8 align(@alignOf(Data)) = undefined;
    @memset(&mint_buffer, 0);
    @memcpy(mint_buffer[0..DISCRIMINATOR_LENGTH], &MintAccount.discriminator);

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = mint_buffer.len,
        .data = mint_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const token_program_info = AccountInfo{
        .id = &token_program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    var accounts = Accounts{
        .token_program = try UncheckedProgram.load(&token_program_info),
        .mint = try MintAccount.load(&mint_info),
    };

    try accounts.mint.validateAllConstraints("mint", accounts);

    owner = PublicKey.default();
    accounts = Accounts{
        .token_program = try UncheckedProgram.load(&token_program_info),
        .mint = try MintAccount.load(&mint_info),
    };
    try std.testing.expectError(error.ConstraintOwner, accounts.mint.validateAllConstraints("mint", accounts));
}

test "Account associated_token constraints validate at runtime" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("AssociatedTokenConstraint"),
        .associated_token = .{
            .mint = "mint",
            .authority = "authority",
            .token_program = "token_program",
        },
    });

    const Accounts = struct {
        authority: Signer,
        mint: *const AccountInfo,
        token_program: UncheckedProgram,
        token: TokenAccount,
    };

    const mint_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const authority_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;
    const associated_token_program_id = comptime sol.PublicKey.comptimeFromBase58(
        "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
    );

    const seeds = .{ &authority_key.bytes, &token_program_key.bytes, &mint_key.bytes };
    const pda = try sol.PublicKey.findProgramAddress(seeds, associated_token_program_id);

    var mint_id = mint_key;
    var authority_id = authority_key;
    var token_program_id = token_program_key;
    var token_id = pda.address;
    var owner = token_program_key;
    var lamports: u64 = 1_000_000;

    var token_buffer: [DISCRIMINATOR_LENGTH + token_state.Account.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&token_buffer, 0);
    @memcpy(token_buffer[0..DISCRIMINATOR_LENGTH], &TokenAccount.discriminator);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mint_key.bytes);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH + 32 .. DISCRIMINATOR_LENGTH + 64], &authority_key.bytes);
    token_buffer[DISCRIMINATOR_LENGTH + token_state.Account.STATE_OFFSET] = 1;

    const token_info = AccountInfo{
        .id = &token_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = token_buffer.len,
        .data = token_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const token_program_info = AccountInfo{
        .id = &token_program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
    };

    var accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };

    try accounts.token.validateAllConstraints("token", accounts);

    const mismatch_mint = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mismatch_mint.bytes);
    accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };
    try std.testing.expectError(error.ConstraintAssociated, accounts.token.validateAllConstraints("token", accounts));

    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mint_key.bytes);
    const bad_id = PublicKey.default();
    token_id = bad_id;
    accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token_program = try UncheckedProgram.load(&token_program_info),
        .token = try TokenAccount.load(&token_info),
    };
    try std.testing.expectError(error.ConstraintAssociated, accounts.token.validateAllConstraints("token", accounts));
}

test "Account associated_token enforces token program owner by default" {
    const token_state = sol.spl.token.state;

    const Data = struct {
        value: u64,
    };

    const TokenAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("AssociatedTokenOwnerConstraint"),
        .associated_token = .{
            .mint = "mint",
            .authority = "authority",
        },
    });

    const Accounts = struct {
        authority: Signer,
        mint: *const AccountInfo,
        token: TokenAccount,
    };

    const mint_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const authority_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    const token_program_key = sol.spl.TOKEN_PROGRAM_ID;
    const associated_token_program_id = comptime sol.PublicKey.comptimeFromBase58(
        "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL",
    );

    const seeds = .{ &authority_key.bytes, &token_program_key.bytes, &mint_key.bytes };
    const pda = try sol.PublicKey.findProgramAddress(seeds, associated_token_program_id);

    var mint_id = mint_key;
    var authority_id = authority_key;
    var token_id = pda.address;
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var token_buffer: [DISCRIMINATOR_LENGTH + token_state.Account.SIZE]u8 align(@alignOf(Data)) = undefined;
    @memset(&token_buffer, 0);
    @memcpy(token_buffer[0..DISCRIMINATOR_LENGTH], &TokenAccount.discriminator);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH .. DISCRIMINATOR_LENGTH + 32], &mint_key.bytes);
    @memcpy(token_buffer[DISCRIMINATOR_LENGTH + 32 .. DISCRIMINATOR_LENGTH + 64], &authority_key.bytes);
    token_buffer[DISCRIMINATOR_LENGTH + token_state.Account.STATE_OFFSET] = 1;

    const token_info = AccountInfo{
        .id = &token_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = token_buffer.len,
        .data = token_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const mint_info = AccountInfo{
        .id = &mint_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .mint = &mint_info,
        .token = try TokenAccount.load(&token_info),
    };

    try std.testing.expectError(error.ConstraintOwner, accounts.token.validateAllConstraints("token", accounts));
}

test "Account accepts token/ata/mint constraints independently" {
    const Data = struct {
        authority: PublicKey,
        mint: PublicKey,
    };

    const TokenOnly = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("TokenOnly"),
        .token_mint = "mint",
        .token_authority = "authority",
    });

    const AtaOnly = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("AtaOnly"),
        .associated_token = .{ .mint = "mint", .authority = "authority" },
    });

    const MintOnly = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("MintOnly"),
        .mint_authority = "authority",
        .mint_decimals = 6,
    });

    try std.testing.expect(TokenOnly.TOKEN_MINT != null);
    try std.testing.expect(AtaOnly.ASSOCIATED_TOKEN != null);
    try std.testing.expect(MintOnly.MINT_AUTHORITY != null);
}

test "Account constraint expression evaluates at runtime" {
    const Data = struct {
        authority: PublicKey,
    };

    const Constrained = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("Constrained"),
        .constraint = constraints_mod.constraint("authority.key() == counter.authority"),
    });

    const Accounts = struct {
        authority: Signer,
        counter: Constrained,
    };

    const authority_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var counter_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var counter_lamports: u64 = 1_000_000;
    var authority_lamports: u64 = 500_000;

    var counter_buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memcpy(counter_buffer[0..DISCRIMINATOR_LENGTH], &Constrained.discriminator);
    const data_ptr: *Data = @ptrCast(@alignCast(counter_buffer[DISCRIMINATOR_LENGTH..].ptr));
    data_ptr.* = .{ .authority = authority_key };

    const counter_info = AccountInfo{
        .id = &counter_id,
        .owner_id = &owner,
        .lamports = &counter_lamports,
        .data_len = counter_buffer.len,
        .data = counter_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var authority_id = authority_key;
    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &authority_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    var accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .counter = try Constrained.load(&counter_info),
    };

    try accounts.counter.validateAllConstraints("counter", accounts);

    data_ptr.authority = PublicKey.default();
    try std.testing.expectError(error.ConstraintRaw, accounts.counter.validateAllConstraints("counter", accounts));
}

test "Account rent_exempt constraint validates at runtime" {
    const Data = struct {
        value: u64,
    };

    const RentAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("RentExempt"),
        .rent_exempt = true,
    });

    const Accounts = struct {
        rent_account: RentAccount,
    };

    var rent_account_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var rent_account_lamports: u64 = 0;

    var rent_buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memcpy(rent_buffer[0..DISCRIMINATOR_LENGTH], &RentAccount.discriminator);
    const data_ptr: *Data = @ptrCast(@alignCast(rent_buffer[DISCRIMINATOR_LENGTH..].ptr));
    data_ptr.* = .{ .value = 1 };

    const rent = sol.rent.Rent.getOrDefault();
    const min_balance = rent.getMinimumBalance(rent_buffer.len);
    if (min_balance > 0) {
        rent_account_lamports = min_balance - 1;
    }

    const rent_info = AccountInfo{
        .id = &rent_account_id,
        .owner_id = &owner,
        .lamports = &rent_account_lamports,
        .data_len = rent_buffer.len,
        .data = rent_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var accounts = Accounts{
        .rent_account = try RentAccount.load(&rent_info),
    };

    if (min_balance > 0) {
        try std.testing.expectError(error.ConstraintRentExempt, accounts.rent_account.validateAllConstraints("rent_account", accounts));
    }

    rent_account_lamports = min_balance;
    accounts = Accounts{
        .rent_account = try RentAccount.load(&rent_info),
    };
    try accounts.rent_account.validateAllConstraints("rent_account", accounts);
}

test "Account zero constraint validates discriminator is zero" {
    const Data = struct {
        value: u64,
    };

    const ZeroAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("ZeroAccount"),
        .zero = true,
    });

    const Accounts = struct {
        zero_account: ZeroAccount,
    };

    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memset(&buffer, 0);

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = buffer.len,
        .data = buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var accounts = Accounts{
        .zero_account = try ZeroAccount.load(&info),
    };
    try accounts.zero_account.validateAllConstraints("zero_account", accounts);

    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &ZeroAccount.discriminator);
    try std.testing.expectError(error.ConstraintZero, ZeroAccount.load(&info));
}

test "Account space constraint validates exact size" {
    const Data = struct {
        value: u64,
    };

    const SpaceAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("SpaceAccount"),
        .space = DISCRIMINATOR_LENGTH + @sizeOf(Data),
    });

    const Accounts = struct {
        account: SpaceAccount,
    };

    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var exact_buffer: [SpaceAccount.SPACE]u8 align(@alignOf(Data)) = undefined;
    @memset(&exact_buffer, 0);
    @memcpy(exact_buffer[0..DISCRIMINATOR_LENGTH], &SpaceAccount.discriminator);

    const exact_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = exact_buffer.len,
        .data = exact_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var accounts = Accounts{
        .account = try SpaceAccount.load(&exact_info),
    };
    try accounts.account.validateAllConstraints("account", accounts);

    var large_buffer: [SpaceAccount.SPACE + 8]u8 align(@alignOf(Data)) = undefined;
    @memset(&large_buffer, 0);
    @memcpy(large_buffer[0..DISCRIMINATOR_LENGTH], &SpaceAccount.discriminator);

    const large_info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = large_buffer.len,
        .data = large_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    accounts = Accounts{
        .account = try SpaceAccount.load(&large_info),
    };
    try std.testing.expectError(error.ConstraintSpace, accounts.account.validateAllConstraints("account", accounts));
}

test "Account owner/address expressions validate at runtime" {
    const Data = struct {
        pub const INIT_SPACE: usize = @sizeOf(@This());
        authority: PublicKey,
    };

    const Constrained = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("OwnerExpr"),
        .attrs = attr_mod.attr.account(.{
            .owner_expr = "authority.key()",
            .address_expr = "authority.key()",
            .space_expr = "8 + INIT_SPACE",
        }),
    });

    const Accounts = struct {
        authority: Signer,
        counter: Constrained,
    };

    const authority_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var counter_id = authority_key;
    var owner = authority_key;
    var counter_lamports: u64 = 1_000_000;
    var authority_lamports: u64 = 500_000;

    var counter_buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memcpy(counter_buffer[0..DISCRIMINATOR_LENGTH], &Constrained.discriminator);
    const data_ptr: *Data = @ptrCast(@alignCast(counter_buffer[DISCRIMINATOR_LENGTH..].ptr));
    data_ptr.* = .{ .authority = authority_key };

    const counter_info = AccountInfo{
        .id = &counter_id,
        .owner_id = &owner,
        .lamports = &counter_lamports,
        .data_len = counter_buffer.len,
        .data = counter_buffer[0..].ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var authority_id = authority_key;
    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &authority_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    var accounts = Accounts{
        .authority = try Signer.load(&authority_info),
        .counter = try Constrained.load(&counter_info),
    };

    try accounts.counter.validateAllConstraints("counter", accounts);
}

test "Account attribute sugar maps macro fields" {
    const FullData = struct {
        authority: PublicKey,
        value: u64,
        bump: u8,
    };

    const owner_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const address_key = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");

    const Full = Account(FullData, .{
        .discriminator = discriminator_mod.accountDiscriminator("FullAttrSugar"),
        .attrs = attr_mod.attr.account(.{
            .mut = true,
            .signer = true,
            .seeds = &.{ seeds_mod.seed("full"), seeds_mod.seedAccount("authority") },
            .bump_field = "bump",
            .init = true,
            .payer = "payer",
            .has_one_fields = &.{ "authority" },
            .close = "destination",
            .realloc = .{ .payer = "payer", .zero_init = true },
            .rent_exempt = true,
            .constraint = "authority.key() == full.authority",
            .owner = owner_key,
            .address = address_key,
            .space = 128,
        }),
    });

    try std.testing.expect(Full.HAS_SEEDS);
    try std.testing.expect(Full.HAS_BUMP);
    try std.testing.expect(Full.BUMP_FIELD != null);
    try std.testing.expect(std.mem.eql(u8, Full.BUMP_FIELD.?, "bump"));
    try std.testing.expect(Full.IS_INIT);
    try std.testing.expect(Full.HAS_MUT);
    try std.testing.expect(Full.HAS_SIGNER);
    try std.testing.expect(Full.PAYER != null);
    try std.testing.expect(Full.HAS_HAS_ONE);
    try std.testing.expect(Full.HAS_CLOSE);
    try std.testing.expect(Full.HAS_REALLOC);
    try std.testing.expect(Full.RENT_EXEMPT);
    try std.testing.expect(Full.CONSTRAINT != null);
    try std.testing.expect(Full.OWNER != null);
    try std.testing.expect(Full.ADDRESS != null);
    try std.testing.expectEqual(@as(usize, 128), Full.SPACE);
    try std.testing.expect(std.mem.eql(u8, Full.HAS_ONE.?[0].field, "authority"));
    try std.testing.expect(std.mem.eql(u8, Full.HAS_ONE.?[0].target, "authority"));
}

test "Account supports executable constraint alone" {
    const Data = struct {
        value: u64,
    };

    const Executable = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("ExecutableOnly"),
        .executable = true,
    });

    try std.testing.expect(Executable.EXECUTABLE);
    try std.testing.expect(!Executable.HAS_MUT);
    try std.testing.expect(!Executable.HAS_SIGNER);
}

test "Account attribute sugar maps seeds program" {
    const ProgramData = struct {
        authority: PublicKey,
    };

    const WithProgram = Account(ProgramData, .{
        .discriminator = discriminator_mod.accountDiscriminator("SeedsProgram"),
        .attrs = attr_mod.attr.account(.{
            .seeds = &.{ seeds_mod.seed("seed"), seeds_mod.seedAccount("authority") },
            .seeds_program = seeds_mod.seedAccount("authority"),
        }),
    });

    try std.testing.expect(WithProgram.HAS_SEEDS);
    try std.testing.expect(WithProgram.SEEDS_PROGRAM != null);
    try std.testing.expect(std.meta.eql(WithProgram.SEEDS_PROGRAM.?, SeedSpec{ .account = "authority" }));
}

// ============================================================================
// Phase 3: Constraint Enforcement Tests
// ============================================================================

const signer_mod = @import("signer.zig");
const Signer = signer_mod.Signer;
const SignerMut = signer_mod.SignerMut;

test "validateHasOneConstraints succeeds when field matches target" {
    // Use extern struct to ensure predictable layout
    const VaultData = extern struct {
        authority: PublicKey,
        balance: u64,
    };

    const Vault = Account(VaultData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Vault"),
        .has_one = &.{
            .{ .field = "authority", .target = "authority" },
        },
    });

    // Create test data
    const authority_key = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var vault_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var vault_lamports: u64 = 1_000_000;
    var authority_lamports: u64 = 500_000;

    // Use proper struct layout
    const DataWithDisc = extern struct {
        disc: [8]u8,
        data: VaultData,
    };
    var vault_buffer: DataWithDisc = undefined;
    vault_buffer.disc = Vault.discriminator;
    vault_buffer.data.authority = authority_key;
    vault_buffer.data.balance = 0;

    const vault_data_ptr: [*]u8 = @ptrCast(&vault_buffer);

    const vault_info = AccountInfo{
        .id = &vault_id,
        .owner_id = &owner,
        .lamports = &vault_lamports,
        .data_len = @sizeOf(DataWithDisc),
        .data = vault_data_ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var authority_id = authority_key;
    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &authority_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    // Load accounts
    const vault = try Vault.load(&vault_info);
    const authority = try Signer.load(&authority_info);

    // Create accounts struct
    const Accounts = struct {
        vault: Vault,
        authority: Signer,
    };
    const accounts = Accounts{ .vault = vault, .authority = authority };

    // Should succeed - authority matches
    try vault.validateHasOneConstraints(accounts);
}

test "validateHasOneConstraints fails when field does not match target" {
    // Use extern struct to ensure predictable layout
    const VaultData = extern struct {
        authority: PublicKey,
        balance: u64,
    };

    const Vault = Account(VaultData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Vault2"),
        .has_one = &.{
            .{ .field = "authority", .target = "authority" },
        },
    });

    // Create test data with DIFFERENT keys
    const stored_authority = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    const actual_authority = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");

    var vault_id = PublicKey.default();
    var owner = PublicKey.default();
    var vault_lamports: u64 = 1_000_000;
    var authority_lamports: u64 = 500_000;

    // Use proper struct layout
    const DataWithDisc = extern struct {
        disc: [8]u8,
        data: VaultData,
    };
    var vault_buffer: DataWithDisc = undefined;
    vault_buffer.disc = Vault.discriminator;
    vault_buffer.data.authority = stored_authority; // Store different authority
    vault_buffer.data.balance = 0;

    const vault_data_ptr: [*]u8 = @ptrCast(&vault_buffer);

    const vault_info = AccountInfo{
        .id = &vault_id,
        .owner_id = &owner,
        .lamports = &vault_lamports,
        .data_len = @sizeOf(DataWithDisc),
        .data = vault_data_ptr,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var authority_id = actual_authority;
    const authority_info = AccountInfo{
        .id = &authority_id,
        .owner_id = &owner,
        .lamports = &authority_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const vault = try Vault.load(&vault_info);
    const authority = try Signer.load(&authority_info);

    const Accounts = struct {
        vault: Vault,
        authority: Signer,
    };
    const accounts = Accounts{ .vault = vault, .authority = authority };

    // Should fail - authority doesn't match stored value
    try std.testing.expectError(error.ConstraintHasOne, vault.validateHasOneConstraints(accounts));
}

test "validateInitConstraint succeeds when payer is signer and writable" {
    const Data = struct {
        value: u64,
    };

    const InitAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("InitConstraint"),
        .init = true,
        .payer = "payer",
    });

    var account_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var lamports: u64 = 0;
    var data: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = [_]u8{0} ** (DISCRIMINATOR_LENGTH + @sizeOf(Data));

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var payer_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var payer_owner = PublicKey.default();
    var payer_lamports: u64 = 1_000_000;
    var payer_data: [0]u8 = .{};
    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &payer_owner,
        .lamports = &payer_lamports,
        .data_len = payer_data.len,
        .data = &payer_data,
        .is_signer = 1,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer = try SignerMut.load(&payer_info);
    const Accounts = struct {
        payer: SignerMut,
        account: InitAccount,
    };

    const data_ptr: *Data = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));
    const account = InitAccount{ .info = &info, .data = data_ptr };
    const accounts = Accounts{ .payer = payer, .account = account };

    try account.validateInitConstraint(accounts);
}

test "validateInitConstraint fails when payer is not signer" {
    const Data = struct {
        value: u64,
    };

    const InitAccount = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("InitConstraintNoSigner"),
        .init = true,
        .payer = "payer",
    });

    var account_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var lamports: u64 = 0;
    var data: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = [_]u8{0} ** (DISCRIMINATOR_LENGTH + @sizeOf(Data));

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = &data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    var payer_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var payer_owner = PublicKey.default();
    var payer_lamports: u64 = 1_000_000;
    var payer_data: [0]u8 = .{};
    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &payer_owner,
        .lamports = &payer_lamports,
        .data_len = payer_data.len,
        .data = &payer_data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const Accounts = struct {
        payer: *const AccountInfo,
        account: InitAccount,
    };

    const data_ptr: *Data = @ptrCast(@alignCast(info.data + DISCRIMINATOR_LENGTH));
    const account = InitAccount{ .info = &info, .data = data_ptr };
    const accounts = Accounts{ .payer = &payer_info, .account = account };

    try std.testing.expectError(error.ConstraintSigner, account.validateInitConstraint(accounts));
}

test "validateCloseConstraint succeeds when destination is writable" {
    const CloseableData = struct {
        value: u64,
    };

    const Closeable = Account(CloseableData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Closeable"),
        .close = "destination",
    });

    var closeable_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var closeable_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;

    var closeable_data: [16]u8 align(@alignOf(CloseableData)) = undefined;
    @memcpy(closeable_data[0..8], &Closeable.discriminator);

    const closeable_info = AccountInfo{
        .id = &closeable_id,
        .owner_id = &owner,
        .lamports = &closeable_lamports,
        .data_len = closeable_data.len,
        .data = &closeable_data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 1, // Writable
        .is_executable = 0,
    };

    const closeable = try Closeable.load(&closeable_info);
    const destination = try SignerMut.load(&dest_info);

    const Accounts = struct {
        closeable: Closeable,
        destination: SignerMut,
    };
    const accounts = Accounts{ .closeable = closeable, .destination = destination };

    // Should succeed
    try closeable.validateCloseConstraint(accounts);
}

test "validateCloseConstraint fails when destination is not writable" {
    const CloseableData = struct {
        value: u64,
    };

    const Closeable = Account(CloseableData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Closeable2"),
        .close = "destination",
    });

    var closeable_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var dest_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var closeable_lamports: u64 = 1_000_000;
    var dest_lamports: u64 = 500_000;

    var closeable_data: [16]u8 align(@alignOf(CloseableData)) = undefined;
    @memcpy(closeable_data[0..8], &Closeable.discriminator);

    const closeable_info = AccountInfo{
        .id = &closeable_id,
        .owner_id = &owner,
        .lamports = &closeable_lamports,
        .data_len = closeable_data.len,
        .data = &closeable_data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const dest_info = AccountInfo{
        .id = &dest_id,
        .owner_id = &owner,
        .lamports = &dest_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0, // NOT writable
        .is_executable = 0,
    };

    const closeable = try Closeable.load(&closeable_info);
    const destination = try Signer.load(&dest_info); // Signer (not SignerMut)

    const Accounts = struct {
        closeable: Closeable,
        destination: Signer,
    };
    const accounts = Accounts{ .closeable = closeable, .destination = destination };

    // Should fail - destination not writable
    try std.testing.expectError(error.ConstraintClose, closeable.validateCloseConstraint(accounts));
}

test "validateReallocConstraint succeeds when payer is signer and writable" {
    const DynamicData = struct {
        len: u32,
    };

    const Dynamic = Account(DynamicData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Dynamic2"),
        .realloc = .{
            .payer = "payer",
            .zero_init = true,
        },
    });

    var dynamic_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var payer_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var dynamic_lamports: u64 = 1_000_000;
    var payer_lamports: u64 = 5_000_000;

    var dynamic_data: [16]u8 align(@alignOf(DynamicData)) = undefined;
    @memcpy(dynamic_data[0..8], &Dynamic.discriminator);

    const dynamic_info = AccountInfo{
        .id = &dynamic_id,
        .owner_id = &owner,
        .lamports = &dynamic_lamports,
        .data_len = dynamic_data.len,
        .data = &dynamic_data,
        .is_signer = 0,
        .is_writable = 1, // Must be writable
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1, // Is signer
        .is_writable = 1, // Is writable
        .is_executable = 0,
    };

    const dynamic = try Dynamic.load(&dynamic_info);
    const payer = try SignerMut.load(&payer_info);

    const Accounts = struct {
        dynamic: Dynamic,
        payer: SignerMut,
    };
    const accounts = Accounts{ .dynamic = dynamic, .payer = payer };

    // Should succeed
    try dynamic.validateReallocConstraint(accounts);
}

test "validateReallocConstraint fails when payer is not signer" {
    const DynamicData = struct {
        len: u32,
    };

    const Dynamic = Account(DynamicData, .{
        .discriminator = discriminator_mod.accountDiscriminator("Dynamic3"),
        .realloc = .{
            .payer = "payer",
            .zero_init = true,
        },
    });

    var dynamic_id = comptime PublicKey.comptimeFromBase58("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA");
    var payer_id = comptime PublicKey.comptimeFromBase58("SysvarRent111111111111111111111111111111111");
    var owner = PublicKey.default();
    var dynamic_lamports: u64 = 1_000_000;
    var payer_lamports: u64 = 5_000_000;

    var dynamic_data: [16]u8 align(@alignOf(DynamicData)) = undefined;
    @memcpy(dynamic_data[0..8], &Dynamic.discriminator);

    const dynamic_info = AccountInfo{
        .id = &dynamic_id,
        .owner_id = &owner,
        .lamports = &dynamic_lamports,
        .data_len = dynamic_data.len,
        .data = &dynamic_data,
        .is_signer = 0,
        .is_writable = 1,
        .is_executable = 0,
    };

    const payer_info = AccountInfo{
        .id = &payer_id,
        .owner_id = &owner,
        .lamports = &payer_lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 0, // NOT a signer
        .is_writable = 1,
        .is_executable = 0,
    };

    const dynamic = try Dynamic.load(&dynamic_info);

    // Can't use SignerMut here because payer is not a signer, so use raw AccountInfo
    const Accounts = struct {
        dynamic: Dynamic,
        payer: *const AccountInfo,
    };
    const accounts = Accounts{ .dynamic = dynamic, .payer = &payer_info };

    // Should fail - payer not signer
    try std.testing.expectError(error.ConstraintRealloc, dynamic.validateReallocConstraint(accounts));
}

test "requiresConstraintValidation returns correct value" {
    // Reuse existing discriminators to avoid comptime branch limit
    const base_disc = TestAccount.discriminator;

    const NoConstraints = Account(TestData, .{
        .discriminator = base_disc,
    });

    const WithHasOne = Account(struct { authority: PublicKey }, .{
        .discriminator = base_disc,
        .has_one = &.{.{ .field = "authority", .target = "authority" }},
    });

    const WithClose = Account(TestData, .{
        .discriminator = base_disc,
        .close = "dest",
    });

    const WithRealloc = Account(TestData, .{
        .discriminator = base_disc,
        .realloc = .{ .payer = "payer" },
    });

    const WithOwnerExpr = Account(TestData, .{
        .discriminator = base_disc,
        .owner_expr = "authority.key()",
    });

    const WithZero = Account(TestData, .{
        .discriminator = base_disc,
        .zero = true,
    });

    const WithSpace = Account(TestData, .{
        .discriminator = base_disc,
        .space = DISCRIMINATOR_LENGTH + @sizeOf(TestData),
    });

    const WithAssociatedToken = Account(TestData, .{
        .discriminator = base_disc,
        .associated_token = .{ .mint = "mint", .authority = "authority" },
    });

    try std.testing.expect(!NoConstraints.requiresConstraintValidation());
    try std.testing.expect(WithHasOne.requiresConstraintValidation());
    try std.testing.expect(WithClose.requiresConstraintValidation());
    try std.testing.expect(WithRealloc.requiresConstraintValidation());
    try std.testing.expect(WithOwnerExpr.requiresConstraintValidation());
    try std.testing.expect(WithZero.requiresConstraintValidation());
    try std.testing.expect(WithSpace.requiresConstraintValidation());
    try std.testing.expect(WithAssociatedToken.requiresConstraintValidation());
}
