//! Zig implementation of Anchor account attribute DSL
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/codegen/accounts/constraints.rs
//!
//! Provides a lightweight attribute list used to configure Account wrappers.

const sol = @import("solana_program_sdk");
const seeds_mod = @import("seeds.zig");
const has_one_mod = @import("has_one.zig");
const realloc_mod = @import("realloc.zig");
const constraints_mod = @import("constraints.zig");

const PublicKey = sol.PublicKey;
const SeedSpec = seeds_mod.SeedSpec;
const HasOneSpec = has_one_mod.HasOneSpec;
const ReallocConfig = realloc_mod.ReallocConfig;
const ConstraintExpr = constraints_mod.ConstraintExpr;

pub const Attr = union(enum) {
    mut: void,
    signer: void,
    zero: void,
    dup: void,
    seeds: []const SeedSpec,
    bump: void,
    bump_field: []const u8,
    seeds_program: SeedSpec,
    init_if_needed: void,
    associated_token_mint: []const u8,
    associated_token_authority: []const u8,
    associated_token_token_program: []const u8,
    token_mint: []const u8,
    token_authority: []const u8,
    token_program: []const u8,
    mint_authority: []const u8,
    mint_freeze_authority: []const u8,
    mint_decimals: u8,
    mint_token_program: []const u8,
    init: void,
    payer: []const u8,
    close: []const u8,
    realloc: ReallocConfig,
    has_one: []const HasOneSpec,
    rent_exempt: void,
    constraint: ConstraintExpr,
    owner: PublicKey,
    owner_expr: []const u8,
    address: PublicKey,
    address_expr: []const u8,
    executable: void,
    space: usize,
    space_expr: []const u8,
};

/// Macro-style account attribute configuration.
///
/// This config mirrors common `#[account(...)]` fields and is intended
/// to be converted into an Attr list via `anchor.attr.account(...)`.
pub const AccountAttrConfig = struct {
    mut: bool = false,
    signer: bool = false,
    zero: bool = false,
    dup: bool = false,
    seeds: ?[]const SeedSpec = null,
    bump: bool = false,
    bump_field: ?[]const u8 = null,
    seeds_program: ?SeedSpec = null,
    init_if_needed: bool = false,
    associated_token_mint: ?[]const u8 = null,
    associated_token_authority: ?[]const u8 = null,
    associated_token_token_program: ?[]const u8 = null,
    token_mint: ?[]const u8 = null,
    token_authority: ?[]const u8 = null,
    token_program: ?[]const u8 = null,
    mint_authority: ?[]const u8 = null,
    mint_freeze_authority: ?[]const u8 = null,
    mint_decimals: ?u8 = null,
    mint_token_program: ?[]const u8 = null,
    init: bool = false,
    payer: ?[]const u8 = null,
    close: ?[]const u8 = null,
    realloc: ?ReallocConfig = null,
    has_one: ?[]const HasOneSpec = null,
    has_one_fields: ?[]const []const u8 = null,
    rent_exempt: bool = false,
    constraint: ?[]const u8 = null,
    owner: ?PublicKey = null,
    owner_expr: ?[]const u8 = null,
    address: ?PublicKey = null,
    address_expr: ?[]const u8 = null,
    executable: bool = false,
    space: ?usize = null,
    space_expr: ?[]const u8 = null,
};

fn hasOneSpecsFromFields(comptime fields: []const []const u8) []const HasOneSpec {
    const specs = comptime blk: {
        var tmp: [fields.len]HasOneSpec = undefined;
        for (fields, 0..) |field_name, index| {
            tmp[index] = .{ .field = field_name, .target = field_name };
        }
        break :blk tmp;
    };
    return specs[0..];
}

fn countAccountAttrs(comptime config: AccountAttrConfig) usize {
    comptime var count: usize = 0;
    if (config.mut) count += 1;
    if (config.signer) count += 1;
    if (config.zero) count += 1;
    if (config.dup) count += 1;
    if (config.seeds != null) count += 1;
    if (config.bump) count += 1;
    if (config.bump_field != null) count += 1;
    if (config.seeds_program != null) count += 1;
    if (config.init_if_needed) count += 1;
    if (config.associated_token_mint != null) count += 1;
    if (config.associated_token_authority != null) count += 1;
    if (config.associated_token_token_program != null) count += 1;
    if (config.token_mint != null) count += 1;
    if (config.token_authority != null) count += 1;
    if (config.token_program != null) count += 1;
    if (config.mint_authority != null) count += 1;
    if (config.mint_freeze_authority != null) count += 1;
    if (config.mint_decimals != null) count += 1;
    if (config.mint_token_program != null) count += 1;
    if (config.init) count += 1;
    if (config.payer != null) count += 1;
    if (config.close != null) count += 1;
    if (config.realloc != null) count += 1;
    if (config.has_one != null) count += 1;
    if (config.has_one_fields != null) count += 1;
    if (config.rent_exempt) count += 1;
    if (config.constraint != null) count += 1;
    if (config.owner != null) count += 1;
    if (config.owner_expr != null) count += 1;
    if (config.address != null) count += 1;
    if (config.address_expr != null) count += 1;
    if (config.executable) count += 1;
    if (config.space != null) count += 1;
    if (config.space_expr != null) count += 1;
    return count;
}

pub const attr = struct {
    pub fn mut() Attr {
        return .{ .mut = {} };
    }

    pub fn signer() Attr {
        return .{ .signer = {} };
    }

    pub fn zero() Attr {
        return .{ .zero = {} };
    }

    pub fn dup() Attr {
        return .{ .dup = {} };
    }

    pub fn seeds(comptime value: []const SeedSpec) Attr {
        seeds_mod.validateSeeds(value);
        return .{ .seeds = value };
    }

    pub fn bump() Attr {
        return .{ .bump = {} };
    }

    pub fn bumpField(comptime value: []const u8) Attr {
        return .{ .bump_field = value };
    }

    pub fn seedsProgram(comptime value: SeedSpec) Attr {
        return .{ .seeds_program = value };
    }

    pub fn initIfNeeded() Attr {
        return .{ .init_if_needed = {} };
    }

    pub fn associatedTokenMint(comptime value: []const u8) Attr {
        return .{ .associated_token_mint = value };
    }

    pub fn associatedTokenAuthority(comptime value: []const u8) Attr {
        return .{ .associated_token_authority = value };
    }

    pub fn associatedTokenTokenProgram(comptime value: []const u8) Attr {
        return .{ .associated_token_token_program = value };
    }

    pub fn tokenMint(comptime value: []const u8) Attr {
        return .{ .token_mint = value };
    }

    pub fn tokenAuthority(comptime value: []const u8) Attr {
        return .{ .token_authority = value };
    }

    pub fn tokenProgram(comptime value: []const u8) Attr {
        return .{ .token_program = value };
    }

    pub fn mintAuthority(comptime value: []const u8) Attr {
        return .{ .mint_authority = value };
    }

    pub fn mintFreezeAuthority(comptime value: []const u8) Attr {
        return .{ .mint_freeze_authority = value };
    }

    pub fn mintDecimals(value: u8) Attr {
        return .{ .mint_decimals = value };
    }

    pub fn mintTokenProgram(comptime value: []const u8) Attr {
        return .{ .mint_token_program = value };
    }

    pub fn init() Attr {
        return .{ .init = {} };
    }

    pub fn payer(comptime value: []const u8) Attr {
        return .{ .payer = value };
    }

    pub fn close(comptime value: []const u8) Attr {
        return .{ .close = value };
    }

    pub fn realloc(comptime config: ReallocConfig) Attr {
        return .{ .realloc = config };
    }

    pub fn hasOne(comptime value: []const HasOneSpec) Attr {
        return .{ .has_one = value };
    }

    pub fn rentExempt() Attr {
        return .{ .rent_exempt = {} };
    }

    pub fn constraint(comptime expr: []const u8) Attr {
        return .{ .constraint = constraints_mod.constraint(expr) };
    }

    pub fn owner(value: PublicKey) Attr {
        return .{ .owner = value };
    }

    pub fn ownerExpr(comptime value: []const u8) Attr {
        return .{ .owner_expr = value };
    }

    pub fn address(value: PublicKey) Attr {
        return .{ .address = value };
    }

    pub fn addressExpr(comptime value: []const u8) Attr {
        return .{ .address_expr = value };
    }

    pub fn executable() Attr {
        return .{ .executable = {} };
    }

    pub fn space(value: usize) Attr {
        return .{ .space = value };
    }

    pub fn spaceExpr(comptime value: []const u8) Attr {
        return .{ .space_expr = value };
    }

    pub fn account(comptime config: AccountAttrConfig) []const Attr {
        if (config.has_one != null and config.has_one_fields != null) {
            @compileError("has_one and has_one_fields are mutually exclusive");
        }
        if (config.owner != null and config.owner_expr != null) {
            @compileError("owner and owner_expr are mutually exclusive");
        }
        if (config.address != null and config.address_expr != null) {
            @compileError("address and address_expr are mutually exclusive");
        }
        if (config.space != null and config.space_expr != null) {
            @compileError("space and space_expr are mutually exclusive");
        }

        const attrs = comptime buildAccountAttrArray(config);
        return attrs[0..];
    }

};

fn buildAccountAttrArray(comptime config: AccountAttrConfig) [countAccountAttrs(config)]Attr {
    const attr_count = comptime countAccountAttrs(config);
    comptime var attrs: [attr_count]Attr = undefined;
    comptime var index: usize = 0;

    if (config.mut) {
        attrs[index] = attr.mut();
        index += 1;
    }
    if (config.signer) {
        attrs[index] = attr.signer();
        index += 1;
    }
    if (config.zero) {
        attrs[index] = attr.zero();
        index += 1;
    }
    if (config.dup) {
        attrs[index] = attr.dup();
        index += 1;
    }
    if (config.seeds) |value| {
        attrs[index] = attr.seeds(value);
        index += 1;
    }
    if (config.bump) {
        attrs[index] = attr.bump();
        index += 1;
    }
    if (config.bump_field) |value| {
        attrs[index] = attr.bumpField(value);
        index += 1;
    }
    if (config.seeds_program) |value| {
        attrs[index] = attr.seedsProgram(value);
        index += 1;
    }
    if (config.init_if_needed) {
        attrs[index] = attr.initIfNeeded();
        index += 1;
    }
    if (config.associated_token_mint) |value| {
        attrs[index] = attr.associatedTokenMint(value);
        index += 1;
    }
    if (config.associated_token_authority) |value| {
        attrs[index] = attr.associatedTokenAuthority(value);
        index += 1;
    }
    if (config.associated_token_token_program) |value| {
        attrs[index] = attr.associatedTokenTokenProgram(value);
        index += 1;
    }
    if (config.token_mint) |value| {
        attrs[index] = attr.tokenMint(value);
        index += 1;
    }
    if (config.token_authority) |value| {
        attrs[index] = attr.tokenAuthority(value);
        index += 1;
    }
    if (config.token_program) |value| {
        attrs[index] = attr.tokenProgram(value);
        index += 1;
    }
    if (config.mint_authority) |value| {
        attrs[index] = attr.mintAuthority(value);
        index += 1;
    }
    if (config.mint_freeze_authority) |value| {
        attrs[index] = attr.mintFreezeAuthority(value);
        index += 1;
    }
    if (config.mint_decimals) |value| {
        attrs[index] = attr.mintDecimals(value);
        index += 1;
    }
    if (config.mint_token_program) |value| {
        attrs[index] = attr.mintTokenProgram(value);
        index += 1;
    }
    if (config.init) {
        attrs[index] = attr.init();
        index += 1;
    }
    if (config.payer) |value| {
        attrs[index] = attr.payer(value);
        index += 1;
    }
    if (config.close) |value| {
        attrs[index] = attr.close(value);
        index += 1;
    }
    if (config.realloc) |value| {
        attrs[index] = attr.realloc(value);
        index += 1;
    }
    if (config.has_one) |value| {
        attrs[index] = attr.hasOne(value);
        index += 1;
    }
    if (config.has_one_fields) |value| {
        attrs[index] = attr.hasOne(hasOneSpecsFromFields(value));
        index += 1;
    }
    if (config.rent_exempt) {
        attrs[index] = attr.rentExempt();
        index += 1;
    }
    if (config.constraint) |value| {
        attrs[index] = attr.constraint(value);
        index += 1;
    }
    if (config.owner) |value| {
        attrs[index] = attr.owner(value);
        index += 1;
    }
    if (config.owner_expr) |value| {
        attrs[index] = attr.ownerExpr(value);
        index += 1;
    }
    if (config.address) |value| {
        attrs[index] = attr.address(value);
        index += 1;
    }
    if (config.address_expr) |value| {
        attrs[index] = attr.addressExpr(value);
        index += 1;
    }
    if (config.executable) {
        attrs[index] = attr.executable();
        index += 1;
    }
    if (config.space) |value| {
        attrs[index] = attr.space(value);
        index += 1;
    }
    if (config.space_expr) |value| {
        attrs[index] = attr.spaceExpr(value);
        index += 1;
    }

    return attrs;
}
