//! sol-anchor-zig: Anchor-like framework for Zig
//!
//! This module provides Anchor-compatible patterns for Solana program
//! development in Zig. It uses comptime metaprogramming instead of Rust
//! proc macros to achieve similar ergonomics.
//!
//! ## Overview
//!
//! The anchor module provides:
//! - **Discriminators**: 8-byte sighash identifiers for accounts and instructions
//! - **Account types**: Type-safe wrappers with automatic validation
//! - **Context**: Instruction context with parsed accounts
//! - **Constraints**: Declarative validation (mut, signer, owner, etc.)
//! - **Error codes**: Anchor-compatible error codes for client interop
//!
//! ## Example
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const sol = anchor.sdk;
//!
//! // Define account state
//! const CounterData = struct {
//!     count: u64,
//!     authority: sol.PublicKey,
//! };
//!
//! // Create typed account wrapper
//! const Counter = anchor.Account(CounterData, .{
//!     .discriminator = anchor.accountDiscriminator("Counter"),
//! });
//!
//! // Define instruction accounts
//! const IncrementAccounts = struct {
//!     authority: anchor.Signer,
//!     counter: Counter,
//! };
//!
//! // Instruction handler
//! fn increment(ctx: anchor.Context(IncrementAccounts)) !void {
//!     ctx.accounts.counter.data.count += 1;
//! }
//! ```
//!
//! ## Phase 1 Features
//!
//! - Account discriminator generation (SHA256 sighash)
//! - Account(T) wrapper with discriminator validation
//! - Signer/SignerMut account types
//! - Program(ID) account type
//! - Context(Accounts) instruction context
//! - Constraint validation (mut, signer, owner, address)
//! - Anchor-compatible error codes
//!
//! ## Phase 2 Features (PDA Support)
//!
//! - Seed type system (literal, account, field references)
//! - PDA validation and derivation helpers
//! - Account initialization via CPI
//! - Bump seeds storage in context
//!
//! ## Phase 3 Features (Advanced Constraints)
//!
//! - has_one constraint: Validate account data field matches another account's key
//! - close constraint: Account closing with lamport transfer to destination
//! - realloc constraint: Dynamic account resizing with rent handling

const std = @import("std");

/// Re-export solana_program_sdk for convenience.
pub const sdk = @import("solana_program_sdk");

// ============================================================================
// Discriminator Module
// ============================================================================

/// Discriminator generation using SHA256 sighash
pub const discriminator = @import("discriminator.zig");

/// Length of discriminator in bytes (8)
pub const DISCRIMINATOR_LENGTH = discriminator.DISCRIMINATOR_LENGTH;

/// Discriminator type (8 bytes)
pub const Discriminator = discriminator.Discriminator;

/// Generate account discriminator
///
/// Creates `sha256("account:<name>")[0..8]`
///
/// Example:
/// ```zig
/// const disc = anchor.accountDiscriminator("Counter");
/// ```
pub const accountDiscriminator = discriminator.accountDiscriminator;

/// Generate instruction discriminator
///
/// Creates `sha256("global:<name>")[0..8]`
///
/// Example:
/// ```zig
/// const disc = anchor.instructionDiscriminator("initialize");
/// ```
pub const instructionDiscriminator = discriminator.instructionDiscriminator;

/// Generate custom sighash discriminator
///
/// Creates `sha256("<namespace>:<name>")[0..8]`
pub const sighash = discriminator.sighash;

// ============================================================================
// Error Module
// ============================================================================

/// Anchor error types and codes
pub const error_mod = @import("error.zig");

/// Anchor framework errors (codes 100-3999)
///
/// Compatible with Anchor error codes for client interoperability.
pub const AnchorError = error_mod.AnchorError;

/// Custom error base (6000+)
pub const CUSTOM_ERROR_BASE = error_mod.CUSTOM_ERROR_BASE;

/// Create custom error code
///
/// Example:
/// ```zig
/// const MyError = enum(u32) {
///     InvalidAmount = anchor.customErrorCode(0),  // 6000
///     Unauthorized = anchor.customErrorCode(1),   // 6001
/// };
/// ```
pub const customErrorCode = error_mod.customErrorCode;

// ============================================================================
// IDL + Codegen
// ============================================================================

/// Anchor IDL generation utilities
pub const idl = @import("idl.zig");

/// Zig client code generation utilities
pub const codegen = @import("codegen.zig");

/// IDL config overrides
pub const IdlConfig = idl.IdlConfig;

/// Instruction descriptor for IDL/codegen
pub const Instruction = idl.Instruction;

/// Generate Anchor-compatible IDL JSON
pub const generateIdlJson = idl.generateJson;

/// Generate Zig client module source
pub const generateZigClient = codegen.generateZigClient;

// ============================================================================
// AccountLoader (Zero-Copy)
// ============================================================================

/// AccountLoader for zero-copy account access
pub const account_loader = @import("account_loader.zig");

/// AccountLoader config
pub const AccountLoaderConfig = account_loader.AccountLoaderConfig;

/// Zero-copy account loader type
pub const AccountLoader = account_loader.AccountLoader;

// ============================================================================
// LazyAccount
// ============================================================================

/// LazyAccount for on-demand deserialization
pub const lazy_account = @import("lazy_account.zig");

/// LazyAccount config
pub const LazyAccountConfig = lazy_account.LazyAccountConfig;

/// LazyAccount type
pub const LazyAccount = lazy_account.LazyAccount;

// ============================================================================
// Program Entry
// ============================================================================

/// Program dispatch helpers (Anchor-style entry)
pub const program_entry = @import("program_entry.zig");

/// Typed program dispatcher
pub const ProgramEntry = program_entry.ProgramEntry;

/// Program dispatch configuration
pub const DispatchConfig = program_entry.DispatchConfig;

/// Fallback handler context
pub const FallbackContext = program_entry.FallbackContext;

// ============================================================================
// Interface + CPI Helpers
// ============================================================================

/// Interface account/program helpers
pub const interface = @import("interface.zig");

/// Interface config
pub const InterfaceConfig = interface.InterfaceConfig;

/// Meta merge strategy for Interface CPI
pub const MetaMergeStrategy = interface.MetaMergeStrategy;

/// Interface program wrapper with multiple allowed IDs
pub const InterfaceProgram = interface.InterfaceProgram;

/// Interface program wrapper for any executable program
pub const InterfaceProgramAny = interface.InterfaceProgramAny;

/// Interface program wrapper without validation
pub const InterfaceProgramUnchecked = interface.InterfaceProgramUnchecked;

/// Interface account wrapper with multiple owners
pub const InterfaceAccount = interface.InterfaceAccount;

/// Interface account info wrapper
pub const InterfaceAccountInfo = interface.InterfaceAccountInfo;

/// Interface account config
pub const InterfaceAccountConfig = interface.InterfaceAccountConfig;

/// Interface account info config
pub const InterfaceAccountInfoConfig = interface.InterfaceAccountInfoConfig;

/// Interface CPI AccountMeta override wrapper
pub const AccountMetaOverride = interface.AccountMetaOverride;

/// Interface CPI instruction builder
pub const Interface = interface.Interface;

// ============================================================================
// CPI Context
// ============================================================================

/// CPI context builder
pub const cpi_context = @import("cpi_context.zig");

/// CPI context builder with default config
pub const CpiContext = cpi_context.CpiContext;

/// CPI context builder with custom interface config
pub const CpiContextWithConfig = cpi_context.CpiContextWithConfig;

// ============================================================================
// SPL Token Helpers
// ============================================================================

/// SPL Token account wrappers and CPI helpers
pub const token = @import("token.zig");

/// SPL Associated Token Account CPI helpers
pub const associated_token = @import("associated_token.zig");

/// Token account wrapper
pub const TokenAccount = token.TokenAccount;

/// Mint account wrapper
pub const Mint = token.Mint;

// ============================================================================
// SPL Memo Helpers
// ============================================================================

/// SPL Memo CPI helpers
pub const memo = @import("memo.zig");

// ============================================================================
// SPL Stake Helpers
// ============================================================================

/// SPL Stake wrappers and CPI helpers
pub const stake = @import("stake.zig");

// ============================================================================
// Event Emission
// ============================================================================

/// Event emission utilities
pub const event = @import("event.zig");

/// Maximum event data size
pub const MAX_EVENT_SIZE = event.MAX_EVENT_SIZE;

/// Event discriminator length
pub const EVENT_DISCRIMINATOR_LENGTH = event.EVENT_DISCRIMINATOR_LENGTH;

/// Emit an event to the Solana program logs
///
/// Events follow Anchor's format: `[discriminator][borsh_serialized_data]`
///
/// Example:
/// ```zig
/// const TransferEvent = struct {
///     from: sol.PublicKey,
///     to: sol.PublicKey,
///     amount: u64,
/// };
///
/// anchor.emitEvent(TransferEvent, .{
///     .from = source_key,
///     .to = dest_key,
///     .amount = 1000,
/// });
/// ```
pub const emitEvent = event.emitEvent;

/// Emit an event with a custom discriminator
pub const emitEventWithDiscriminator = event.emitEventWithDiscriminator;

/// Get the discriminator for an event type
pub const getEventDiscriminator = event.getEventDiscriminator;

// ============================================================================
// Type-Safe DSL
// ============================================================================

/// Type-Safe DSL for Solana Program Development
///
/// Provides a concise builder-pattern syntax with compile-time type safety:
///
/// ```zig
/// const dsl = anchor.dsl;
///
/// const Initialize = dsl.Instr("initialize",
///     dsl.Accounts(.{
///         .payer = dsl.SignerMut,
///         .counter = dsl.Init(CounterData, .{ .payer = .payer }),
///         .system_program = dsl.SystemProgram,
///     }),
///     struct { initial_value: u64 },
/// );
///
/// pub fn initialize(ctx: Initialize.Ctx, args: Initialize.Args) !void {
///     ctx.accounts.counter.data.count = args.initial_value;
/// }
/// ```
///
/// Available markers:
/// - Account types: Signer, SignerMut, Unchecked, SystemAccount, StakeAccount
/// - Data accounts: Data, Init, PDA, Close, Realloc, Opt
/// - Token accounts: Token, Mint, ATA
/// - Programs: Prog, SystemProgram, TokenProgram, Token2022Program, etc.
/// - Sysvars: RentSysvar, ClockSysvar, etc.
/// - Events: Event, eventField
pub const dsl = @import("typed_dsl.zig");

// ============================================================================
// Constraints Module
// ============================================================================

/// Constraint types and validation
pub const constraints = @import("constraints.zig");

/// Constraint specification for account validation
///
/// Example:
/// ```zig
/// const my_constraints = anchor.Constraints{
///     .mut = true,
///     .signer = true,
/// };
/// ```
pub const Constraints = constraints.Constraints;

/// Constraint expression helper
pub const constraint = constraints.constraint;
/// Typed constraint expression builder
pub const constraint_typed = constraints.constraint_typed;

/// Constraint expression descriptor
pub const ConstraintExpr = constraints.ConstraintExpr;

/// Validate constraints against an account
pub const validateConstraints = constraints.validateConstraints;

/// Validate constraints, returning error on failure
pub const validateConstraintsOrError = constraints.validateConstraintsOrError;

/// Constraint validation errors
pub const ConstraintError = constraints.ConstraintError;

// ============================================================================
// Account Module
// ============================================================================

/// Account wrapper with discriminator validation
pub const account = @import("account.zig");

/// Account configuration
pub const AccountConfig = account.AccountConfig;
pub const AssociatedTokenConfig = account.AssociatedTokenConfig;

/// Account attribute DSL
pub const attr = @import("attr.zig").attr;

/// Account attribute type
pub const Attr = @import("attr.zig").Attr;

/// Account attribute config for macro-style syntax
pub const AccountAttrConfig = @import("attr.zig").AccountAttrConfig;

/// Typed selector for Accounts struct fields.
pub fn accountField(comptime AccountsType: type, comptime field: std.meta.FieldEnum(AccountsType)) []const u8 {
    return @tagName(field);
}

/// Typed selector for account data struct fields.
pub fn dataField(comptime Data: type, comptime field: std.meta.FieldEnum(Data)) []const u8 {
    return @tagName(field);
}

/// Typed field list helper for Accounts struct fields.
pub fn accountFields(
    comptime AccountsType: type,
    comptime fields: []const std.meta.FieldEnum(AccountsType),
) []const []const u8 {
    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, index| {
        names[index] = accountField(AccountsType, field);
    }
    return names[0..];
}

/// Typed field list helper for account data struct fields.
pub fn dataFields(
    comptime Data: type,
    comptime fields: []const std.meta.FieldEnum(Data),
) []const []const u8 {
    comptime var names: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, index| {
        names[index] = dataField(Data, field);
    }
    return names[0..];
}

/// Account wrapper type
///
/// Provides type-safe access to account data with automatic
/// discriminator verification.
///
/// Example:
/// ```zig
/// const Counter = anchor.Account(struct {
///     count: u64,
/// }, .{
///     .discriminator = anchor.accountDiscriminator("Counter"),
/// });
/// ```
pub const Account = account.Account;

/// Account wrapper with field-level attrs.
pub const AccountField = account.AccountField;

/// Account loading errors
pub const AccountError = account.AccountError;

// ============================================================================
// Signer Module
// ============================================================================

/// Signer account types
pub const signer = @import("signer.zig");

/// Signer account type (read-only)
///
/// Validates that an account is a signer of the transaction.
///
/// Example:
/// ```zig
/// const MyAccounts = struct {
///     authority: anchor.Signer,
/// };
/// ```
pub const Signer = signer.Signer;

/// Mutable signer account type
///
/// Validates that an account is both a signer and writable.
/// Use for payer accounts.
///
/// Example:
/// ```zig
/// const MyAccounts = struct {
///     payer: anchor.SignerMut,
/// };
/// ```
pub const SignerMut = signer.SignerMut;

/// Configurable signer type
pub const SignerWith = signer.SignerWith;

/// Signer configuration
pub const SignerConfig = signer.SignerConfig;

/// Signer validation errors
pub const SignerError = signer.SignerError;

// ============================================================================
// System Account Module
// ============================================================================

/// System account wrappers
pub const system_account = @import("system_account.zig");

/// System-owned account (read-only)
pub const SystemAccount = system_account.SystemAccountConst;

/// System-owned account (mutable)
pub const SystemAccountMut = system_account.SystemAccountMut;

/// Configurable system account wrapper
pub const SystemAccountWith = system_account.SystemAccount;

// ============================================================================
// Stake Account Module
// ============================================================================

/// Stake account (read-only)
pub const StakeAccount = stake.StakeAccountConst;

/// Stake account (mutable)
pub const StakeAccountMut = stake.StakeAccountMut;

/// Configurable stake account wrapper
pub const StakeAccountWith = stake.StakeAccount;

// ============================================================================
// Program Module
// ============================================================================

/// Program account types
pub const program = @import("program.zig");

/// Program account with expected ID validation
///
/// Validates that an account is an executable program with the expected ID.
///
/// Example:
/// ```zig
/// const MyAccounts = struct {
///     system_program: anchor.Program(system_program.ID),
/// };
/// ```
pub const Program = program.Program;

/// Unchecked program reference
///
/// Validates executable but not program ID.
pub const UncheckedProgram = program.UncheckedProgram;

/// Program validation errors
pub const ProgramError = program.ProgramError;

// ============================================================================
// Sysvar Module
// ============================================================================

/// Sysvar account wrapper types
pub const sysvar_account = @import("sysvar_account.zig");

/// Sysvar account wrapper with address validation.
pub const Sysvar = sysvar_account.Sysvar;

/// Sysvar account wrapper with data parsing.
pub const SysvarData = sysvar_account.SysvarData;

/// Sysvar data wrappers
pub const ClockData = sysvar_account.ClockData;
pub const RentData = sysvar_account.RentData;
pub const EpochScheduleData = sysvar_account.EpochScheduleData;
pub const SlotHashesData = sysvar_account.SlotHashesData;
pub const SlotHistoryData = sysvar_account.SlotHistoryData;
pub const EpochRewardsData = sysvar_account.EpochRewardsData;
pub const LastRestartSlotData = sysvar_account.LastRestartSlotData;

/// Sysvar id-only wrappers
pub const ClockSysvar = sysvar_account.ClockSysvar;
pub const RentSysvar = sysvar_account.RentSysvar;
pub const EpochScheduleSysvar = sysvar_account.EpochScheduleSysvar;
pub const SlotHashesSysvar = sysvar_account.SlotHashesSysvar;
pub const SlotHistorySysvar = sysvar_account.SlotHistorySysvar;
pub const EpochRewardsSysvar = sysvar_account.EpochRewardsSysvar;
pub const LastRestartSlotSysvar = sysvar_account.LastRestartSlotSysvar;

// ============================================================================
// Context Module
// ============================================================================

/// Instruction context types
pub const context = @import("context.zig");

/// Instruction context
///
/// Provides access to parsed accounts, program ID, and remaining accounts.
///
/// Example:
/// ```zig
/// fn initialize(ctx: anchor.Context(MyAccounts)) !void {
///     // Access accounts via ctx.accounts
///     // Access program ID via ctx.program_id
/// }
/// ```
pub const Context = context.Context;

/// Bump seeds storage
pub const Bumps = context.Bumps;

/// Load accounts from account info slice
pub const loadAccounts = context.loadAccounts;

/// Parse full context from program inputs
pub const parseContext = context.parseContext;

/// Load accounts with dependency resolution for non-literal seeds
///
/// This function handles the two-phase loading required when seeds reference
/// other accounts (via seedAccount) or account data fields (via seedField).
///
/// Example:
/// ```zig
/// const result = try anchor.loadAccountsWithDependencies(
///     MyAccounts,
///     &program_id,
///     account_infos,
/// );
/// const accounts = result.accounts;
/// const bumps = result.bumps;
/// ```
pub const loadAccountsWithDependencies = context.loadAccountsWithDependencies;

/// Context loading errors
pub const ContextError = context.ContextError;

/// Convert a slice of accounts into a slice of Account.Info using a caller-provided buffer.
///
/// Returns the filled slice (min of accounts.len and out.len).
pub fn accountsToInfoSlice(accounts: anytype, out: []sdk.account.Account.Info) []const sdk.account.Account.Info {
    const AccountsType = @TypeOf(accounts);
    const info = @typeInfo(AccountsType);
    if (info != .slice) {
        @compileError("accountsToInfoSlice expects a slice");
    }
    const Child = info.slice.child;
    if (!@hasDecl(Child, "info")) {
        @compileError("accountsToInfoSlice expects elements with info() method");
    }

    const count = @min(accounts.len, out.len);
    for (accounts[0..count], 0..) |acct, i| {
        out[i] = acct.info();
    }

    return out[0..count];
}

// ============================================================================
// Phase 2: Seeds Module
// ============================================================================

/// Seed types for PDA derivation
pub const seeds = @import("seeds.zig");

/// Seed specification type
///
/// Defines how to obtain a seed value for PDA derivation.
pub const SeedSpec = seeds.SeedSpec;

/// Create a literal seed
///
/// Example:
/// ```zig
/// const my_seeds = &.{ anchor.seed("counter"), anchor.seed("v1") };
/// ```
pub const seed = seeds.seed;

/// Create an account reference seed
///
/// References another account's public key as a seed.
///
/// Example:
/// ```zig
/// const my_seeds = &.{ anchor.seed("user"), anchor.seedAccount("authority") };
/// ```
pub const seedAccount = seeds.seedAccount;

/// Create an account reference seed using typed field selector.
pub fn seedAccountField(comptime AccountsType: type, comptime field: std.meta.FieldEnum(AccountsType)) SeedSpec {
    return seeds.seedAccount(accountField(AccountsType, field));
}

/// Create a field reference seed
///
/// References a field in the account data as a seed.
///
/// Example:
/// ```zig
/// const my_seeds = &.{ anchor.seed("owned_by"), anchor.seedField("owner") };
/// ```
pub const seedField = seeds.seedField;

/// Create a field reference seed using typed data field selector.
pub fn seedDataField(comptime Data: type, comptime field: std.meta.FieldEnum(Data)) SeedSpec {
    return seeds.seedField(dataField(Data, field));
}

/// Create a bump reference seed
pub const seedBump = seeds.seedBump;

/// Maximum number of seeds
pub const MAX_SEEDS = seeds.MAX_SEEDS;

/// Maximum seed length
pub const MAX_SEED_LEN = seeds.MAX_SEED_LEN;

/// Seed buffer for runtime resolution
pub const SeedBuffer = seeds.SeedBuffer;

/// Seed resolution errors
pub const SeedError = seeds.SeedError;

/// Append a seed to a SeedBuffer
pub const appendSeed = seeds.appendSeed;

/// Append a bump seed (single byte) to a SeedBuffer
pub const appendBumpSeed = seeds.appendBumpSeed;

// ============================================================================
// Phase 2: PDA Module
// ============================================================================

/// PDA validation and derivation utilities
pub const pda = @import("pda.zig");

/// Validate that an account matches the expected PDA
///
/// Example:
/// ```zig
/// const bump = try anchor.validatePda(
///     counter_account.key(),
///     &.{ "counter", &authority.bytes },
///     program_id,
/// );
/// ```
pub const validatePda = pda.validatePda;

/// Validate PDA using runtime-resolved seeds (slice-based)
///
/// Use when seeds are resolved at runtime (e.g., seedAccount, seedField).
///
/// Example:
/// ```zig
/// var seed_buffer = anchor.SeedBuffer{};
/// try anchor.appendSeed(&seed_buffer, "counter");
/// try anchor.appendSeed(&seed_buffer, &authority_key.bytes);
///
/// const bump = try anchor.validatePdaRuntime(
///     counter_account.key(),
///     seed_buffer.asSlice(),
///     &program_id,
/// );
/// ```
pub const validatePdaRuntime = pda.validatePdaRuntime;

/// Validate PDA with known bump seed
pub const validatePdaWithBump = pda.validatePdaWithBump;

/// Derive a PDA address and bump seed
pub const derivePda = pda.derivePda;

/// Create a PDA address with known bump
pub const createPdaAddress = pda.createPdaAddress;

/// Check if an address is a valid PDA
pub const isPda = pda.isPda;

/// PDA validation errors
pub const PdaError = pda.PdaError;

// ============================================================================
// Phase 2: Init Module
// ============================================================================

/// Account initialization utilities
pub const init = @import("init.zig");

/// Configuration for account initialization
pub const InitConfig = init.InitConfig;
/// Configuration for batch account initialization
pub const BatchInitConfig = init.BatchInitConfig;

/// Get rent-exempt balance for an account
///
/// Example:
/// ```zig
/// const lamports = try anchor.rentExemptBalance(Counter.SPACE);
/// ```
pub const rentExemptBalance = init.rentExemptBalance;

/// Calculate rent-exempt balance using defaults
pub const rentExemptBalanceDefault = init.rentExemptBalanceDefault;

/// Create a new account via CPI
pub const createAccount = init.createAccount;
/// Create multiple accounts via CPI
pub const createAccounts = init.createAccounts;

/// Create an account at a PDA via CPI
///
/// Example:
/// ```zig
/// try anchor.createAccountAtPda(
///     payer_info,
///     counter_info,
///     &my_program_id,
///     Counter.SPACE,
///     &.{ "counter", &authority.bytes },
///     bump,
///     &my_program_id,
///     system_program_info,
/// );
/// ```
pub const createAccountAtPda = init.createAccountAtPda;

/// Check if an account is uninitialized
pub const isUninitialized = init.isUninitialized;

/// Validate account is ready for initialization
pub const validateForInit = init.validateForInit;

/// Account initialization errors
pub const InitError = init.InitError;

// ============================================================================
// Phase 3: Has-One Module
// ============================================================================

/// Has-one constraint validation
pub const has_one = @import("has_one.zig");

/// Has-one constraint specification
///
/// Defines a relationship between a field in account data and another account.
///
/// Example:
/// ```zig
/// const Vault = anchor.Account(VaultData, .{
///     .discriminator = anchor.accountDiscriminator("Vault"),
///     .has_one = &.{
///         .{ .field = "authority", .target = "authority" },
///     },
/// });
/// ```
pub const HasOneSpec = has_one.HasOneSpec;

/// Typed helper for has_one specs.
pub fn hasOneSpec(
    comptime Data: type,
    comptime data_field: std.meta.FieldEnum(Data),
    comptime AccountsType: type,
    comptime target_field: std.meta.FieldEnum(AccountsType),
) HasOneSpec {
    return .{
        .field = dataField(Data, data_field),
        .target = accountField(AccountsType, target_field),
    };
}

/// Validate has_one constraint
///
/// Example:
/// ```zig
/// try anchor.validateHasOne(VaultData, &vault.data, "authority", authority.key());
/// ```
pub const validateHasOne = has_one.validateHasOne;

/// Validate has_one constraint with raw bytes
pub const validateHasOneBytes = has_one.validateHasOneBytes;

/// Check if has_one constraint is satisfied (returns bool)
pub const checkHasOne = has_one.checkHasOne;

/// Get field bytes for has_one validation
pub const getHasOneFieldBytes = has_one.getHasOneFieldBytes;

/// Has-one validation errors
pub const HasOneError = has_one.HasOneError;

// ============================================================================
// Phase 3: Close Module
// ============================================================================

/// Account closing utilities
pub const close = @import("close.zig");

/// Close an account, transferring lamports to destination
///
/// Transfers all lamports and zeros account data. The Solana runtime
/// automatically garbage collects the account afterward.
///
/// Example:
/// ```zig
/// try anchor.closeAccount(account_info, destination_info);
/// ```
pub const closeAccount = close.closeAccount;

/// Close account with typed wrapper
pub const closeTyped = close.close;

/// Check if account can be closed to destination
pub const canClose = close.canClose;

/// Get lamports that would be transferred on close
pub const getCloseRefund = close.getCloseRefund;

/// Check if account is already closed (zero lamports)
pub const isClosed = close.isClosed;

/// Account close errors
pub const CloseError = close.CloseError;

// ============================================================================
// Phase 3: Realloc Module
// ============================================================================

/// Account reallocation utilities
pub const realloc = @import("realloc.zig");

/// Maximum account size (10 MB)
pub const MAX_ACCOUNT_SIZE = realloc.MAX_ACCOUNT_SIZE;

/// Realloc configuration
///
/// Example:
/// ```zig
/// const Dynamic = anchor.Account(Data, .{
///     .discriminator = anchor.accountDiscriminator("Dynamic"),
///     .realloc = .{
///         .payer = "payer",
///         .zero_init = true,
///     },
/// });
/// ```
pub const ReallocConfig = realloc.ReallocConfig;

/// Reallocate account data to new size
///
/// Handles rent payment/refund based on size change.
///
/// Example:
/// ```zig
/// try anchor.reallocAccount(account_info, new_size, payer_info, true);
/// ```
pub const reallocAccount = realloc.reallocAccount;

/// Calculate rent difference for reallocation
pub const calculateRentDiff = realloc.calculateRentDiff;

/// Validate a realloc operation without executing
pub const validateRealloc = realloc.validateRealloc;

/// Get rent required for a given size
pub const rentForSize = realloc.rentForSize;

/// Check if realloc would require payment
pub const requiresPayment = realloc.requiresPayment;

/// Check if realloc would produce refund
pub const producesRefund = realloc.producesRefund;

/// Account realloc errors
pub const ReallocError = realloc.ReallocError;

// ============================================================================
// Tests
// ============================================================================

test "anchor module exports" {
    // Phase 1 exports
    _ = DISCRIMINATOR_LENGTH;
    _ = Discriminator;
    _ = accountDiscriminator;
    _ = instructionDiscriminator;
    _ = AnchorError;
    _ = Constraints;
    _ = Account;
    _ = AccountField;
    _ = AccountConfig;
    _ = AssociatedTokenConfig;
    _ = Signer;
    _ = SignerMut;
    _ = SystemAccount;
    _ = SystemAccountMut;
    _ = StakeAccount;
    _ = StakeAccountMut;
    _ = Program;
    _ = Context;
    _ = Sysvar;
    _ = SysvarData;
    _ = ClockData;
    _ = RentData;
    _ = EpochScheduleData;
    _ = SlotHashesData;
    _ = SlotHistoryData;
    _ = EpochRewardsData;
    _ = LastRestartSlotData;
    _ = ClockSysvar;
    _ = RentSysvar;
    _ = EpochScheduleSysvar;
    _ = SlotHashesSysvar;
    _ = SlotHistorySysvar;
    _ = EpochRewardsSysvar;
    _ = LastRestartSlotSysvar;
    _ = CpiContext;
    _ = CpiContextWithConfig;
    _ = token;
    _ = associated_token;
    _ = memo;
    _ = stake;
    _ = TokenAccount;
    _ = Mint;

    // Phase 2 exports
    _ = SeedSpec;
    _ = seed;
    _ = seedAccount;
    _ = seedAccountField;
    _ = seedField;
    _ = seedDataField;
    _ = validatePda;
    _ = derivePda;
    _ = rentExemptBalance;
    _ = InitError;

    // Phase 3 exports
    _ = HasOneSpec;
    _ = hasOneSpec;
    _ = validateHasOne;
    _ = HasOneError;
    _ = closeAccount;
    _ = CloseError;
    _ = ReallocConfig;
    _ = reallocAccount;
    _ = ReallocError;
    _ = MAX_ACCOUNT_SIZE;
}

test "typed field helpers" {
    const AccountsType = struct {
        payer: SignerMut,
        authority: Signer,
    };

    const Data = struct {
        authority: sdk.PublicKey,
        bump: u8,
    };

    try std.testing.expectEqualStrings("payer", accountField(AccountsType, .payer));
    try std.testing.expectEqualStrings("authority", dataField(Data, .authority));

    const account_seed = seedAccountField(AccountsType, .payer);
    switch (account_seed) {
        .account => |name| try std.testing.expectEqualStrings("payer", name),
        else => try std.testing.expect(false),
    }

    const data_seed = seedDataField(Data, .authority);
    switch (data_seed) {
        .field => |name| try std.testing.expectEqualStrings("authority", name),
        else => try std.testing.expect(false),
    }

    const spec = hasOneSpec(Data, .authority, AccountsType, .authority);
    try std.testing.expectEqualStrings("authority", spec.field);
    try std.testing.expectEqualStrings("authority", spec.target);
}

test "discriminator submodule" {
    _ = discriminator;
}

test "error submodule" {
    _ = error_mod;
}

test "constraints submodule" {
    _ = constraints;
}

test "account submodule" {
    _ = account;
}

test "signer submodule" {
    _ = signer;
}

test "program submodule" {
    _ = program;
}

test "context submodule" {
    _ = context;
}

// Phase 2 submodule tests
test "seeds submodule" {
    _ = seeds;
}

test "pda submodule" {
    _ = pda;
}

test "init submodule" {
    _ = init;
}

// Phase 3 submodule tests
test "has_one submodule" {
    _ = has_one;
}

test "close submodule" {
    _ = close;
}

test "realloc submodule" {
    _ = realloc;
}
