//! Zig implementation of Anchor Context
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/context.rs
//!
//! Context provides the instruction context for Anchor programs. It wraps
//! the parsed accounts struct and provides access to the program ID and
//! any remaining accounts not defined in the accounts struct.
//!
//! ## Example
//! ```zig
//! const MyAccounts = struct {
//!     authority: anchor.Signer,
//!     counter: anchor.Account(Counter, .{ .discriminator = ... }),
//! };
//!
//! fn initialize(ctx: anchor.Context(MyAccounts), initial_value: u64) !void {
//!     ctx.accounts.counter.data.value = initial_value;
//!     ctx.accounts.counter.data.authority = ctx.accounts.authority.key().*;
//! }
//! ```

const std = @import("std");
const seeds_mod = @import("seeds.zig");
const pda_mod = @import("pda.zig");
const init_mod = @import("init.zig");
const sol = @import("solana_program_sdk");

// Import from parent SDK
const sdk_account = sol.account;
const PublicKey = sol.PublicKey;

const AccountInfo = sdk_account.Account.Info;
const SeedSpec = seeds_mod.SeedSpec;

fn unwrapOptionalType(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .optional) {
        return info.optional.child;
    }
    return T;
}

fn isAccountWrapper(comptime T: type) bool {
    return @hasDecl(T, "DataType") and @hasDecl(T, "discriminator");
}

fn expectAccountField(comptime Accounts: type, comptime name: []const u8) void {
    if (!@hasField(Accounts, name)) {
        @compileError("account constraint references unknown Accounts field: " ++ name);
    }
}

fn validateSeedAccountRef(comptime Accounts: type, seed: SeedSpec) void {
    switch (seed) {
        .account => |name| expectAccountField(Accounts, name),
        .bump => |name| expectAccountField(Accounts, name),
        else => {},
    }
}

/// Validate seedField references against account DataType
fn validateSeedFieldRef(comptime DataType: type, comptime field_name: []const u8) void {
    if (!@hasField(DataType, field_name)) {
        @compileError("seedField references unknown data field: " ++ field_name ++ " in " ++ @typeName(DataType));
    }

    // Verify the field type is valid for seeds (PublicKey or byte array)
    const field_type = @TypeOf(@field(@as(DataType, undefined), field_name));
    const is_valid_type = comptime blk: {
        if (field_type == PublicKey) break :blk true;
        const info = @typeInfo(field_type);
        if (info == .array) {
            if (info.array.child == u8) break :blk true;
        }
        break :blk false;
    };

    if (!is_valid_type) {
        @compileError("seedField '" ++ field_name ++ "' must be PublicKey or [N]u8, found " ++ @typeName(field_type));
    }
}

fn validateAccountRefs(comptime Accounts: type) void {
    const fields = @typeInfo(Accounts).@"struct".fields;

    inline for (fields) |field| {
        const FieldType = unwrapOptionalType(field.type);
        if (!isAccountWrapper(FieldType)) continue;

        if (FieldType.PAYER) |name| {
            expectAccountField(Accounts, name);
        }
        if (FieldType.CLOSE) |name| {
            expectAccountField(Accounts, name);
        }
        if (FieldType.BUMP_FIELD) |name| {
            expectAccountField(Accounts, name);
        }
        if (FieldType.HAS_ONE) |list| {
            inline for (list) |spec| {
                expectAccountField(Accounts, spec.target);
            }
        }
        if (FieldType.ASSOCIATED_TOKEN) |cfg| {
            expectAccountField(Accounts, cfg.mint);
            expectAccountField(Accounts, cfg.authority);
            if (cfg.token_program) |name| {
                expectAccountField(Accounts, name);
            }
        }
        if (FieldType.TOKEN_MINT) |name| {
            expectAccountField(Accounts, name);
        }
        if (FieldType.TOKEN_AUTHORITY) |name| {
            expectAccountField(Accounts, name);
        }
        if (FieldType.SEEDS) |seeds| {
            inline for (seeds) |seed| {
                validateSeedAccountRef(Accounts, seed);
                // Validate seedField references against account DataType
                switch (seed) {
                    .field => |field_name| {
                        if (@hasDecl(FieldType, "DataType")) {
                            validateSeedFieldRef(FieldType.DataType, field_name);
                        }
                    },
                    else => {},
                }
            }
        }
        if (FieldType.SEEDS_PROGRAM) |seed| {
            validateSeedAccountRef(Accounts, seed);
        }
    }
}

/// Bump seeds storage for PDA accounts
///
/// Stores bump seeds discovered during account loading.
/// Keys are account field names, values are bump seeds.
pub const Bumps = struct {
    /// Storage for bump seeds (field name hash -> bump)
    data: [MAX_BUMPS]BumpEntry = undefined,
    len: usize = 0,

    /// Maximum number of PDA bumps that can be stored.
    /// Increased from 16 to 32 to support complex programs.
    const MAX_BUMPS = 32;

    const BumpEntry = struct {
        name_hash: u64,
        bump: u8,
    };

    /// Get bump seed for a field name
    pub fn get(self: *const Bumps, comptime name: []const u8) ?u8 {
        const hash = comptime hashName(name);
        for (self.data[0..self.len]) |entry| {
            if (entry.name_hash == hash) {
                return entry.bump;
            }
        }
        return null;
    }

    /// Set bump seed for a field name
    pub fn set(self: *Bumps, comptime name: []const u8, bump: u8) void {
        const hash = comptime hashName(name);

        // Check if already exists
        for (self.data[0..self.len]) |*entry| {
            if (entry.name_hash == hash) {
                entry.bump = bump;
                return;
            }
        }

        // Add new entry
        if (self.len < MAX_BUMPS) {
            self.data[self.len] = .{
                .name_hash = hash,
                .bump = bump,
            };
            self.len += 1;
        }
    }

    /// Get bump seed by runtime key (hash value)
    ///
    /// Use this when the field name is not known at compile time.
    pub fn getByKey(self: *const Bumps, key: u64) ?u8 {
        for (self.data[0..self.len]) |entry| {
            if (entry.name_hash == key) {
                return entry.bump;
            }
        }
        return null;
    }

    /// Set bump seed by runtime key (hash value)
    pub fn setByKey(self: *Bumps, key: u64, bump: u8) void {
        // Check if already exists
        for (self.data[0..self.len]) |*entry| {
            if (entry.name_hash == key) {
                entry.bump = bump;
                return;
            }
        }

        // Add new entry
        if (self.len < MAX_BUMPS) {
            self.data[self.len] = .{
                .name_hash = key,
                .bump = bump,
            };
            self.len += 1;
        }
    }

    /// Get the number of stored bumps
    pub fn count(self: *const Bumps) usize {
        return self.len;
    }

    /// Check if a bump exists for a field name
    pub fn contains(self: *const Bumps, comptime name: []const u8) bool {
        return self.get(name) != null;
    }

    /// FNV-1a hash for field name lookup (compile-time)
    ///
    /// Uses FNV-1a 64-bit hash for better collision resistance
    /// compared to simple polynomial hash.
    fn hashName(comptime name: []const u8) u64 {
        comptime {
            // FNV-1a 64-bit constants
            const FNV_OFFSET: u64 = 0xcbf29ce484222325;
            const FNV_PRIME: u64 = 0x100000001b3;

            var hash: u64 = FNV_OFFSET;
            for (name) |c| {
                hash ^= c;
                hash *%= FNV_PRIME;
            }
            return hash;
        }
    }

    /// FNV-1a hash for field name lookup (runtime)
    ///
    /// Use this when the field name is not known at compile time.
    pub fn hashNameRuntime(name: []const u8) u64 {
        // FNV-1a 64-bit constants
        const FNV_OFFSET: u64 = 0xcbf29ce484222325;
        const FNV_PRIME: u64 = 0x100000001b3;

        var hash: u64 = FNV_OFFSET;
        for (name) |c| {
            hash ^= c;
            hash *%= FNV_PRIME;
        }
        return hash;
    }
};

/// Instruction context for Anchor programs
///
/// Provides type-safe access to parsed accounts and program metadata.
///
/// Type Parameters:
/// - `Accounts`: Struct type defining the expected accounts
///
/// Anchor equivalent: `Context<'_, '_, '_, 'info, T>`
pub fn Context(comptime Accounts: type) type {
    comptime {
        validateAccountRefs(Accounts);
    }

    return struct {
        const Self = @This();

        /// Parsed and validated accounts
        accounts: Accounts,

        /// Program ID of the executing program
        program_id: *const PublicKey,

        /// Accounts not defined in the Accounts struct
        ///
        /// Used for dynamic account access (e.g., variable number of accounts)
        remaining_accounts: []const AccountInfo,

        /// Bump seeds for PDA accounts
        ///
        /// Populated when loading accounts with seeds constraints
        bumps: Bumps,

        /// Create a new context
        ///
        /// This is typically called by the framework, not user code.
        pub fn new(
            accounts: Accounts,
            program_id: *const PublicKey,
            remaining_accounts: []const AccountInfo,
            bumps: Bumps,
        ) Self {
            return Self{
                .accounts = accounts,
                .program_id = program_id,
                .remaining_accounts = remaining_accounts,
                .bumps = bumps,
            };
        }

        /// Create context with only accounts (no remaining accounts)
        pub fn fromAccounts(
            accounts: Accounts,
            program_id: *const PublicKey,
        ) Self {
            return Self{
                .accounts = accounts,
                .program_id = program_id,
                .remaining_accounts = &[_]AccountInfo{},
                .bumps = Bumps{},
            };
        }

        /// Get a specific bump seed by field name
        ///
        /// Returns null if the field has no associated bump.
        pub fn getBump(self: *const Self, comptime field_name: []const u8) ?u8 {
            return self.bumps.get(field_name);
        }

        /// Emit an event to the Solana program logs
        ///
        /// Events are emitted via `sol_log_data` and can be parsed by clients
        /// subscribing to program logs. The format follows Anchor's event
        /// encoding: `[discriminator][borsh_serialized_data]`.
        ///
        /// Example:
        /// ```zig
        /// const TransferEvent = struct {
        ///     from: sol.PublicKey,
        ///     to: sol.PublicKey,
        ///     amount: u64,
        /// };
        ///
        /// fn transfer(ctx: anchor.Context(TransferAccounts), amount: u64) !void {
        ///     // ... transfer logic ...
        ///     ctx.emit(TransferEvent, .{
        ///         .from = ctx.accounts.from.key().*,
        ///         .to = ctx.accounts.to.key().*,
        ///         .amount = amount,
        ///     });
        /// }
        /// ```
        pub fn emit(self: *const Self, comptime EventType: type, event_data: EventType) void {
            _ = self; // Context state not needed for event emission
            const event_mod = @import("event.zig");
            event_mod.emitEvent(EventType, event_data);
        }
    };
}

/// Result of loading accounts with PDA validation
pub const LoadAccountsResult = struct {
    fn AccountsType(comptime Accounts: type) type {
        return struct {
            accounts: Accounts,
            bumps: Bumps,
        };
    }
};

/// Load accounts from account info slice
///
/// Iterates over struct fields and loads each account type.
/// This is the core deserialization logic for instruction contexts.
///
/// Note: This basic version does NOT validate PDA seeds. For PDA validation,
/// use `loadAccountsWithPda` which requires a program_id.
///
/// Example:
/// ```zig
/// const accounts = try loadAccounts(MyAccounts, account_infos);
/// ```
fn loadInitAccount(comptime FieldType: type, info: *const AccountInfo) !FieldType {
    if (@hasDecl(FieldType, "IS_INIT_IF_NEEDED") and FieldType.IS_INIT_IF_NEEDED) {
        if (init_mod.isUninitialized(info)) {
            return FieldType.loadUnchecked(info);
        }
        return FieldType.load(info);
    }
    return FieldType.loadUnchecked(info);
}

fn finalizeInitAccounts(
    comptime Accounts: type,
    infos: []const AccountInfo,
    accounts: *Accounts,
) !void {
    const fields = @typeInfo(Accounts).@"struct".fields;

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        if (!@hasDecl(FieldType, "IS_INIT") or !FieldType.IS_INIT) continue;

        if (@hasDecl(FieldType, "IS_INIT_IF_NEEDED") and FieldType.IS_INIT_IF_NEEDED) {
            if (!init_mod.isUninitialized(info)) {
                continue;
            }
        }

        const account = &@field(accounts.*, field.name);
        try account.validateInitConstraint(accounts.*);
        @field(accounts.*, field.name) = try FieldType.init(info);
    }
}

pub fn loadAccounts(comptime Accounts: type, infos: []const AccountInfo) !Accounts {
    const fields = @typeInfo(Accounts).@"struct".fields;

    if (infos.len < fields.len) {
        return error.AccountNotEnoughAccountKeys;
    }

    var accounts: Accounts = undefined;

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
            @field(accounts, field.name) = try loadInitAccount(FieldType, info);
        } else if (@hasDecl(FieldType, "load")) {
            @field(accounts, field.name) = try FieldType.load(info);
        } else {
            // For raw AccountInfo pointers
            @field(accounts, field.name) = info;
        }
    }

    return accounts;
}

/// Load accounts with PDA validation for literal-only seeds
///
/// For each account type with HAS_SEEDS and literal-only seeds,
/// validates the PDA address and stores the bump in the returned Bumps.
///
/// For accounts with seedAccount/seedField references, you must call
/// loadWithPda manually after loading the referenced accounts.
///
/// Note: This function also validates Phase 3 constraints (has_one, close, realloc, constraint)
/// after all accounts are loaded.
///
/// Example:
/// ```zig
/// const result = try loadAccountsWithPda(MyAccounts, &program_id, account_infos);
/// const accounts = result.accounts;
/// const bumps = result.bumps;
/// ```
pub fn loadAccountsWithPda(
    comptime Accounts: type,
    program_id: *const PublicKey,
    infos: []const AccountInfo,
) !struct { accounts: Accounts, bumps: Bumps } {
    const fields = @typeInfo(Accounts).@"struct".fields;

    if (infos.len < fields.len) {
        return error.AccountNotEnoughAccountKeys;
    }

    var accounts: Accounts = undefined;
    var bumps = Bumps{};

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        // Check if this field type has PDA seeds
        if (@hasDecl(FieldType, "HAS_SEEDS") and FieldType.HAS_SEEDS) {
            // Check if all seeds are literals (can be resolved at compile time)
            if (@hasDecl(FieldType, "SEEDS")) {
                if (FieldType.SEEDS) |seed_specs| {
                    if (seeds_mod.areAllLiteralSeeds(seed_specs)) {
                        // Resolve literal seeds at comptime
                        const resolved_seeds = seeds_mod.resolveComptimeSeeds(seed_specs);

                        // Load with PDA validation
                        if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
                            const bump = pda_mod.validatePda(info.id, resolved_seeds, program_id) catch {
                                return error.ConstraintSeeds;
                            };
                            bumps.set(field.name, bump);
                            @field(accounts, field.name) = try loadInitAccount(FieldType, info);
                        } else if (@hasDecl(FieldType, "loadWithPda")) {
                            const result = try FieldType.loadWithPda(info, resolved_seeds, program_id);
                            @field(accounts, field.name) = result.account;
                            bumps.set(field.name, result.bump);
                        } else {
                            @field(accounts, field.name) = try FieldType.load(info);
                        }
                    } else {
                        // Non-literal seeds: load without PDA validation
                        // User must call loadWithPda manually with resolved seeds
                        if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
                            @field(accounts, field.name) = try loadInitAccount(FieldType, info);
                        } else if (@hasDecl(FieldType, "load")) {
                            @field(accounts, field.name) = try FieldType.load(info);
                        } else {
                            @field(accounts, field.name) = info;
                        }
                    }
                } else {
                    // No seeds defined, normal load
                    if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
                        @field(accounts, field.name) = try loadInitAccount(FieldType, info);
                    } else if (@hasDecl(FieldType, "load")) {
                        @field(accounts, field.name) = try FieldType.load(info);
                    } else {
                        @field(accounts, field.name) = info;
                    }
                }
            } else {
                // No SEEDS constant, normal load
                if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
                    @field(accounts, field.name) = try loadInitAccount(FieldType, info);
                } else if (@hasDecl(FieldType, "load")) {
                    @field(accounts, field.name) = try FieldType.load(info);
                } else {
                    @field(accounts, field.name) = info;
                }
            }
        } else if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
            @field(accounts, field.name) = try loadInitAccount(FieldType, info);
        } else if (@hasDecl(FieldType, "load")) {
            // No PDA seeds, normal load
            @field(accounts, field.name) = try FieldType.load(info);
        } else {
            // For raw AccountInfo pointers
            @field(accounts, field.name) = info;
        }
    }

    try validateDuplicateMutableAccounts(Accounts, &accounts);

    // Phase 3: Validate constraints after all accounts are loaded
    try validatePhase3Constraints(Accounts, &accounts);
    try finalizeInitAccounts(Accounts, infos, &accounts);

    return .{ .accounts = accounts, .bumps = bumps };
}

/// Load accounts with automatic PDA seed resolution for all seed types
///
/// Unlike `loadAccountsWithPda` which only handles literal-only seeds,
/// this function automatically resolves seedAccount and seedField references
/// by first loading all accounts, then resolving seeds and validating PDAs.
///
/// Seed resolution order:
/// 1. Load all accounts (without PDA validation)
/// 2. For each account with seeds:
///    - Resolve literal seeds directly
///    - Resolve seedAccount by getting the referenced account's public key
///    - Resolve seedField by reading the field from the account's data
///    - Resolve seedBump from previously validated PDAs
/// 3. Validate PDA addresses and store bumps
/// 4. Run Phase 3 constraint validation
///
/// Note: seedField resolution requires the referenced data to already be deserialized,
/// which means the account must be loaded before the field can be accessed.
///
/// Example:
/// ```zig
/// const result = try loadAccountsWithDependencies(MyAccounts, &program_id, account_infos);
/// const accounts = result.accounts;
/// const bumps = result.bumps;
/// ```
pub fn loadAccountsWithDependencies(
    comptime Accounts: type,
    program_id: *const PublicKey,
    infos: []const AccountInfo,
) !struct { accounts: Accounts, bumps: Bumps } {
    const fields = @typeInfo(Accounts).@"struct".fields;

    if (infos.len < fields.len) {
        return error.AccountNotEnoughAccountKeys;
    }

    // Phase 1: Load all accounts without PDA validation
    var accounts: Accounts = undefined;

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
            @field(accounts, field.name) = try loadInitAccount(FieldType, info);
        } else if (@hasDecl(FieldType, "load")) {
            @field(accounts, field.name) = try FieldType.load(info);
        } else {
            @field(accounts, field.name) = info;
        }
    }

    // Phase 2: Resolve seeds and validate PDAs
    var bumps = Bumps{};

    inline for (fields, 0..) |field, i| {
        const FieldType = field.type;
        const info = &infos[i];

        // Skip if no PDA seeds
        if (!@hasDecl(FieldType, "HAS_SEEDS") or !FieldType.HAS_SEEDS) continue;
        if (!@hasDecl(FieldType, "SEEDS")) continue;

        const seed_specs = FieldType.SEEDS orelse continue;

        // If all seeds are literals, we can resolve at comptime
        if (seeds_mod.areAllLiteralSeeds(seed_specs)) {
            const resolved_seeds = seeds_mod.resolveComptimeSeeds(seed_specs);

            if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
                const bump = pda_mod.validatePda(info.id, resolved_seeds, program_id) catch {
                    return error.ConstraintSeeds;
                };
                bumps.set(field.name, bump);
                @field(accounts, field.name) = try loadInitAccount(FieldType, info);
            } else if (@hasDecl(FieldType, "loadWithPda")) {
                const result = try FieldType.loadWithPda(info, resolved_seeds, program_id);
                @field(accounts, field.name) = result.account;
                bumps.set(field.name, result.bump);
            }
        } else {
            // Runtime seed resolution required
            var seed_buffer = seeds_mod.SeedBuffer{};

            inline for (seed_specs) |spec| {
                switch (spec) {
                    .literal => |lit| {
                        try seeds_mod.appendSeed(&seed_buffer, lit);
                    },
                    .account => |account_name| {
                        // Get public key from referenced account
                        const ref_account = @field(accounts, account_name);
                        const RefType = @TypeOf(ref_account);

                        // Check if it's an Account wrapper with key() method
                        if (@hasDecl(RefType, "key")) {
                            const key_ptr = ref_account.key();
                            try seeds_mod.appendSeed(&seed_buffer, &key_ptr.*.bytes);
                        } else {
                            // Handle AccountInfo or *AccountInfo
                            const ActualType = if (@typeInfo(RefType) == .pointer)
                                @typeInfo(RefType).pointer.child
                            else
                                RefType;

                            if (@hasField(ActualType, "id")) {
                                // AccountInfo has id field (which is *PublicKey)
                                const info_ptr = if (@typeInfo(RefType) == .pointer)
                                    ref_account
                                else
                                    &ref_account;
                                try seeds_mod.appendSeed(&seed_buffer, &info_ptr.id.*.bytes);
                            } else {
                                return error.AccountNotFound;
                            }
                        }
                    },
                    .field => |field_name| {
                        // Get field value from account data
                        const account = @field(accounts, field.name);
                        if (@hasDecl(@TypeOf(account), "data")) {
                            const data = account.data;
                            const DataType = @TypeOf(data);
                            const ActualDataType = if (@typeInfo(DataType) == .pointer)
                                @typeInfo(DataType).pointer.child
                            else
                                DataType;

                            if (@hasField(ActualDataType, field_name)) {
                                const data_ptr = if (@typeInfo(DataType) == .pointer) &data.* else &data;
                                const field_ptr = &@field(data_ptr.*, field_name);
                                const SeedFieldType = @TypeOf(field_ptr.*);

                                if (SeedFieldType == PublicKey) {
                                    try seeds_mod.appendSeed(&seed_buffer, &field_ptr.*.bytes);
                                } else {
                                    const seed_field_info = @typeInfo(SeedFieldType);
                                    if (seed_field_info == .array and seed_field_info.array.child == u8) {
                                        try seeds_mod.appendSeed(&seed_buffer, field_ptr.*);
                                    } else {
                                        return error.FieldNotFound;
                                    }
                                }
                            } else {
                                return error.FieldNotFound;
                            }
                        } else {
                            return error.FieldNotFound;
                        }
                    },
                    .bump => |bump_name| {
                        // Get bump from previously validated PDA
                        const bump_value = bumps.get(bump_name) orelse return error.BumpNotFound;
                        try seeds_mod.appendBumpSeed(&seed_buffer, bump_value);
                    },
                }
            }

            // Validate PDA with resolved seeds using pda module
            const bump_value = pda_mod.validatePdaRuntime(
                info.id,
                seed_buffer.asSlice(),
                program_id,
            ) catch {
                return error.ConstraintSeeds;
            };
            bumps.set(field.name, bump_value);
        }
    }

    try validateDuplicateMutableAccounts(Accounts, &accounts);

    // Phase 3: Validate constraints after all accounts are loaded
    try validatePhase3Constraints(Accounts, &accounts);
    try finalizeInitAccounts(Accounts, infos, &accounts);

    return .{ .accounts = accounts, .bumps = bumps };
}

fn validateDuplicateMutableAccounts(comptime Accounts: type, accounts: *const Accounts) !void {
    const fields = @typeInfo(Accounts).@"struct".fields;

    var seen_keys: [fields.len]PublicKey = undefined;
    var seen_count: usize = 0;

    inline for (fields) |field| {
        const FieldType = field.type;

        if (!@hasDecl(FieldType, "HAS_MUT") or !FieldType.HAS_MUT) {
            continue;
        }
        if (@hasDecl(FieldType, "IS_DUP") and FieldType.IS_DUP) {
            continue;
        }
        if (@hasDecl(FieldType, "IS_INIT") and FieldType.IS_INIT) {
            continue;
        }
        if (@hasDecl(FieldType, "IS_INIT_IF_NEEDED") and FieldType.IS_INIT_IF_NEEDED) {
            continue;
        }
        if (!@hasDecl(FieldType, "toAccountInfo")) {
            continue;
        }

        const account = @field(accounts.*, field.name);
        const info = account.toAccountInfo();
        const key = info.id.*;

        var idx: usize = 0;
        while (idx < seen_count) : (idx += 1) {
            if (seen_keys[idx].equals(key)) {
                return error.ConstraintDuplicateMutableAccount;
            }
        }

        seen_keys[seen_count] = key;
        seen_count += 1;
    }
}

/// Validate Phase 3 constraints (has_one, close, realloc, constraint) for all accounts
///
/// This function iterates over all account fields and validates their
/// configured constraints against other accounts in the struct.
///
/// Called automatically by loadAccountsWithPda and parseContext.
pub fn validatePhase3Constraints(comptime Accounts: type, accounts: *const Accounts) !void {
    const fields = @typeInfo(Accounts).@"struct".fields;

    inline for (fields) |field| {
        const FieldType = field.type;
        // Check if this field type has Phase 3 constraint validation
        if (@hasDecl(FieldType, "validateAllConstraints")) {
            const account = &@field(accounts.*, field.name);
            try account.validateAllConstraints(field.name, accounts.*);
        }
    }
}

/// Parse full context from program inputs
///
/// This is the main entry point for instruction handling.
/// Parses accounts, validates PDAs (for literal-only seeds), and creates the full context.
///
/// For accounts with HAS_SEEDS and literal-only seeds, PDA validation is
/// performed automatically and bumps are stored in ctx.bumps.
///
/// For accounts with seedAccount/seedField references, you must:
/// 1. Use parseContextBasic() to skip PDA validation
/// 2. Manually validate PDAs using account.loadWithPda() with resolved seeds
///
/// Example:
/// ```zig
/// pub fn processInstruction(
///     program_id: *const PublicKey,
///     accounts: []const AccountInfo,
///     _: []const u8,
/// ) !void {
///     const ctx = try parseContext(MyAccounts, program_id, accounts);
///     // Access bumps: ctx.bumps.get("counter")
/// }
/// ```
pub fn parseContext(
    comptime Accounts: type,
    program_id: *const PublicKey,
    infos: []const AccountInfo,
) !Context(Accounts) {
    const fields = @typeInfo(Accounts).@"struct".fields;

    // Load accounts with PDA validation for literal-only seeds
    const result = try loadAccountsWithPda(Accounts, program_id, infos);

    // Remaining accounts are those beyond the defined fields
    const remaining = if (infos.len > fields.len)
        infos[fields.len..]
    else
        &[_]AccountInfo{};

    return Context(Accounts).new(
        result.accounts,
        program_id,
        remaining,
        result.bumps,
    );
}

/// Parse context without PDA validation
///
/// Use this when you need manual control over PDA validation,
/// such as when seeds reference other accounts.
///
/// Example:
/// ```zig
/// const ctx = try parseContextBasic(MyAccounts, program_id, accounts);
/// // Manually validate PDA after loading referenced accounts
/// ```
pub fn parseContextBasic(
    comptime Accounts: type,
    program_id: *const PublicKey,
    infos: []const AccountInfo,
) !Context(Accounts) {
    const fields = @typeInfo(Accounts).@"struct".fields;

    const accounts = try loadAccounts(Accounts, infos);

    // Remaining accounts are those beyond the defined fields
    const remaining = if (infos.len > fields.len)
        infos[fields.len..]
    else
        &[_]AccountInfo{};

    return Context(Accounts).new(
        accounts,
        program_id,
        remaining,
        Bumps{},
    );
}

/// Account loading errors
pub const ContextError = error{
    AccountNotEnoughAccountKeys,
};

// ============================================================================
// Tests
// ============================================================================

const signer_mod = @import("signer.zig");
const Signer = signer_mod.Signer;
const account_mod = @import("account.zig");
const Account = account_mod.Account;
const discriminator_mod = @import("discriminator.zig");
const DISCRIMINATOR_LENGTH = discriminator_mod.DISCRIMINATOR_LENGTH;

test "Context creation" {
    const TestAccounts = struct {
        authority: Signer,
    };

    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const signer = try Signer.load(&info);
    var program_id = PublicKey.default();

    const ctx = Context(TestAccounts).fromAccounts(
        TestAccounts{ .authority = signer },
        &program_id,
    );

    try std.testing.expectEqual(&program_id, ctx.program_id);
    try std.testing.expectEqual(@as(usize, 0), ctx.remaining_accounts.len);
}

test "Bumps storage and retrieval" {
    var bumps = Bumps{};

    bumps.set("counter", 255);
    bumps.set("authority", 254);

    try std.testing.expectEqual(@as(?u8, 255), bumps.get("counter"));
    try std.testing.expectEqual(@as(?u8, 254), bumps.get("authority"));
    try std.testing.expectEqual(@as(?u8, null), bumps.get("unknown"));
}

test "loadAccounts parses struct fields" {
    const TestAccounts = struct {
        signer1: Signer,
        signer2: Signer,
    };

    var id1 = PublicKey.default();
    var id2 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var lamports1: u64 = 1000;
    var lamports2: u64 = 2000;

    const infos = [_]AccountInfo{
        AccountInfo{
            .id = &id1,
            .owner_id = &owner,
            .lamports = &lamports1,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
        AccountInfo{
            .id = &id2,
            .owner_id = &owner,
            .lamports = &lamports2,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
    };

    const accounts = try loadAccounts(TestAccounts, &infos);
    try std.testing.expectEqual(&id1, accounts.signer1.key());
    try std.testing.expectEqual(&id2, accounts.signer2.key());
}

test "loadAccounts fails with insufficient accounts" {
    const TestAccounts = struct {
        signer1: Signer,
        signer2: Signer,
    };

    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;

    const infos = [_]AccountInfo{
        AccountInfo{
            .id = &id,
            .owner_id = &owner,
            .lamports = &lamports,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
    };

    try std.testing.expectError(error.AccountNotEnoughAccountKeys, loadAccounts(TestAccounts, &infos));
}

test "parseContext includes remaining accounts" {
    const TestAccounts = struct {
        authority: Signer,
    };

    var id1 = PublicKey.default();
    var id2 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    var program_id = PublicKey.default();

    const infos = [_]AccountInfo{
        AccountInfo{
            .id = &id1,
            .owner_id = &owner,
            .lamports = &lamports,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
        AccountInfo{
            .id = &id2,
            .owner_id = &owner,
            .lamports = &lamports,
            .data_len = 0,
            .data = undefined,
            .is_signer = 0,
            .is_writable = 0,
            .is_executable = 0,
        },
    };

    const ctx = try parseContext(TestAccounts, &program_id, &infos);

    try std.testing.expectEqual(@as(usize, 1), ctx.remaining_accounts.len);
    try std.testing.expectEqual(&id2, ctx.remaining_accounts[0].id);
}

// ============================================================================
// Phase 2: Enhanced Bumps Tests
// ============================================================================

test "Bumps getByKey and setByKey" {
    var bumps = Bumps{};

    const key1 = Bumps.hashNameRuntime("counter");
    const key2 = Bumps.hashNameRuntime("vault");

    bumps.setByKey(key1, 255);
    bumps.setByKey(key2, 254);

    try std.testing.expectEqual(@as(?u8, 255), bumps.getByKey(key1));
    try std.testing.expectEqual(@as(?u8, 254), bumps.getByKey(key2));
    try std.testing.expectEqual(@as(?u8, null), bumps.getByKey(12345));
}

test "Bumps count" {
    var bumps = Bumps{};

    try std.testing.expectEqual(@as(usize, 0), bumps.count());

    bumps.set("a", 1);
    try std.testing.expectEqual(@as(usize, 1), bumps.count());

    bumps.set("b", 2);
    try std.testing.expectEqual(@as(usize, 2), bumps.count());

    // Setting existing key doesn't increase count
    bumps.set("a", 3);
    try std.testing.expectEqual(@as(usize, 2), bumps.count());
}

test "Bumps contains" {
    var bumps = Bumps{};

    bumps.set("counter", 255);

    try std.testing.expect(bumps.contains("counter"));
    try std.testing.expect(!bumps.contains("unknown"));
}

test "Bumps hashNameRuntime matches comptime hash" {
    // The runtime hash should match the comptime hash for the same string
    const runtime_hash = Bumps.hashNameRuntime("counter");
    var bumps = Bumps{};
    bumps.set("counter", 42);

    // If they match, getByKey should find the value set by comptime set
    try std.testing.expectEqual(@as(?u8, 42), bumps.getByKey(runtime_hash));
}

test "Context getBump delegates to bumps" {
    const TestAccounts = struct {
        authority: Signer,
    };

    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    var program_id = PublicKey.default();

    const info = AccountInfo{
        .id = &id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = undefined,
        .is_signer = 1,
        .is_writable = 0,
        .is_executable = 0,
    };

    const signer = try Signer.load(&info);

    var bumps = Bumps{};
    bumps.set("pda_account", 254);

    const ctx = Context(TestAccounts).new(
        TestAccounts{ .authority = signer },
        &program_id,
        &[_]AccountInfo{},
        bumps,
    );

    try std.testing.expectEqual(@as(?u8, 254), ctx.getBump("pda_account"));
    try std.testing.expectEqual(@as(?u8, null), ctx.getBump("unknown"));
}

test "loadAccountsWithPda returns accounts and empty bumps for non-PDA accounts" {
    const TestAccounts = struct {
        signer1: Signer,
        signer2: Signer,
    };

    var id1 = PublicKey.default();
    var id2 = comptime PublicKey.comptimeFromBase58("11111111111111111111111111111111");
    var owner = PublicKey.default();
    var lamports1: u64 = 1000;
    var lamports2: u64 = 2000;
    var program_id = PublicKey.default();

    const infos = [_]AccountInfo{
        AccountInfo{
            .id = &id1,
            .owner_id = &owner,
            .lamports = &lamports1,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
        AccountInfo{
            .id = &id2,
            .owner_id = &owner,
            .lamports = &lamports2,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
    };

    const result = try loadAccountsWithPda(TestAccounts, &program_id, &infos);

    // Check accounts loaded correctly
    try std.testing.expectEqual(&id1, result.accounts.signer1.key());
    try std.testing.expectEqual(&id2, result.accounts.signer2.key());

    // Check no bumps for non-PDA accounts
    try std.testing.expectEqual(@as(usize, 0), result.bumps.count());
}

test "loadAccountsWithPda rejects duplicate mutable accounts without dup" {
    const Data = struct {
        value: u64,
    };

    const Mutable = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("DupMutable"),
        .mut = true,
    });

    const Accounts = struct {
        first: Mutable,
        second: Mutable,
    };

    var program_id = PublicKey.default();
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memset(&buffer, 0);
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &Mutable.discriminator);

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

    const infos = [_]AccountInfo{ info, info };

    try std.testing.expectError(error.ConstraintDuplicateMutableAccount, loadAccountsWithPda(Accounts, &program_id, &infos));
}

test "loadAccountsWithPda allows duplicate mutable accounts with dup" {
    const Data = struct {
        value: u64,
    };

    const Mutable = Account(Data, .{
        .discriminator = discriminator_mod.accountDiscriminator("DupMutableOk"),
        .mut = true,
    });

    const MutableDup = Account(Data, .{
        .discriminator = Mutable.discriminator,
        .mut = true,
        .dup = true,
    });

    const Accounts = struct {
        first: Mutable,
        second: MutableDup,
    };

    var program_id = PublicKey.default();
    var account_id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1_000_000;

    var buffer: [DISCRIMINATOR_LENGTH + @sizeOf(Data)]u8 align(@alignOf(Data)) = undefined;
    @memset(&buffer, 0);
    @memcpy(buffer[0..DISCRIMINATOR_LENGTH], &Mutable.discriminator);

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

    const infos = [_]AccountInfo{ info, info };

    _ = try loadAccountsWithPda(Accounts, &program_id, &infos);
}

test "parseContextBasic creates context without PDA validation" {
    const TestAccounts = struct {
        authority: Signer,
    };

    var id = PublicKey.default();
    var owner = PublicKey.default();
    var lamports: u64 = 1000;
    var program_id = PublicKey.default();

    const infos = [_]AccountInfo{
        AccountInfo{
            .id = &id,
            .owner_id = &owner,
            .lamports = &lamports,
            .data_len = 0,
            .data = undefined,
            .is_signer = 1,
            .is_writable = 0,
            .is_executable = 0,
        },
    };

    const ctx = try parseContextBasic(TestAccounts, &program_id, &infos);

    try std.testing.expectEqual(&id, ctx.accounts.authority.key());
    try std.testing.expectEqual(&program_id, ctx.program_id);
    try std.testing.expectEqual(@as(usize, 0), ctx.bumps.count());
}

test "LoadAccountsResult type is properly defined" {
    // Verify LoadAccountsResult helper type can be used
    const ResultType = LoadAccountsResult.AccountsType(struct {
        signer: Signer,
    });

    try std.testing.expect(@hasField(ResultType, "accounts"));
    try std.testing.expect(@hasField(ResultType, "bumps"));
}
