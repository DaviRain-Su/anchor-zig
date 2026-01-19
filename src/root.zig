//! sol-anchor-zig: High-Performance Anchor Framework for Zig
//!
//! ## Recommended: zero_cu API (5-7 CU)
//!
//! For new projects, use the zero_cu API for optimal performance:
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_cu;
//! const sol = anchor.sdk;
//!
//! const CounterData = struct {
//!     count: u64,
//!     authority: sol.PublicKey,
//! };
//!
//! const IncrementAccounts = struct {
//!     authority: zero.Signer(0),
//!     counter: zero.Account(CounterData, .{
//!         .owner = PROGRAM_ID,
//!     }),
//! };
//!
//! pub fn increment(ctx: zero.Ctx(IncrementAccounts)) !void {
//!     ctx.accounts.counter.getMut().count += 1;
//! }
//!
//! comptime {
//!     zero.entry(IncrementAccounts, "increment", increment);
//! }
//! ```
//!
//! ## Performance Comparison
//!
//! | API | CU Overhead | Use Case |
//! |-----|-------------|----------|
//! | **zero_cu** | **5-7 CU** | New projects, performance-critical |
//! | Standard | ~150 CU | Complex validation, IDL generation |
//!
//! ## Standard API (Legacy)
//!
//! The standard API provides full Anchor compatibility:
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//!
//! const Counter = anchor.Account(CounterData, .{
//!     .discriminator = anchor.accountDiscriminator("Counter"),
//! });
//!
//! fn increment(ctx: anchor.Context(IncrementAccounts)) !void {
//!     ctx.accounts.counter.data.count += 1;
//! }
//! ```

const std = @import("std");

/// Re-export solana_program_sdk for convenience.
pub const sdk = @import("solana_program_sdk");

// ============================================================================
// ⭐ RECOMMENDED: Zero-CU Framework (5-7 CU)
// ============================================================================

/// Zero-CU Framework - High-level API with zero runtime overhead
///
/// ## Account Types
/// - `zero.Signer(size)` - Signer account
/// - `zero.Mut(T)` - Mutable account with typed data
/// - `zero.Readonly(T)` - Readonly account
/// - `zero.Account(T, .{...})` - Account with constraints
///
/// ## Constraints
/// - `.owner = PUBKEY` - Owner validation
/// - `.seeds = &.{...}` - PDA validation
/// - `.has_one = &.{"field"}` - Field match validation
/// - `.discriminator = [8]u8` - Discriminator check
///
/// ## Entry Points
/// - `zero.entry(Accounts, "name", handler)` - Single instruction (5 CU)
/// - `zero.entryValidated(...)` - With auto-validation
/// - `zero.multi(Accounts, .{...})` - Multi-instruction (7 CU)
///
/// ## CPI Helpers
/// - `zero.createAccount(...)` - Create account
/// - `zero.closeAccount(...)` - Close account
/// - `zero.transferLamports(...)` - Transfer lamports
/// - `zero.rentExemptBalance(space)` - Get rent exempt balance
pub const zero_cu = @import("zero_cu.zig");

// ============================================================================
// Discriminator Module (Used by both APIs)
// ============================================================================

/// Discriminator generation using SHA256 sighash
pub const discriminator = @import("discriminator.zig");

/// Length of discriminator in bytes (8)
pub const DISCRIMINATOR_LENGTH = discriminator.DISCRIMINATOR_LENGTH;

/// Discriminator type (8 bytes)
pub const Discriminator = discriminator.Discriminator;

/// Generate account discriminator: `sha256("account:<name>")[0..8]`
pub const accountDiscriminator = discriminator.accountDiscriminator;

/// Generate instruction discriminator: `sha256("global:<name>")[0..8]`
pub const instructionDiscriminator = discriminator.instructionDiscriminator;

/// Generate custom sighash discriminator
pub const sighash = discriminator.sighash;

/// Fast discriminator validation using u64 comparison
pub const validateDiscriminatorFast = discriminator.validateDiscriminatorFast;

/// Check if discriminator is zero (uninitialized account)
pub const isDiscriminatorZero = discriminator.isDiscriminatorZero;

/// Convert discriminator to u64 for fast comparison
pub const discriminatorToU64 = discriminator.discriminatorToU64;

// ============================================================================
// Error Module
// ============================================================================

/// Anchor error types and codes
pub const error_mod = @import("error.zig");

/// Anchor framework errors (codes 100-3999)
pub const AnchorError = error_mod.AnchorError;

/// Custom error base (6000+)
pub const CUSTOM_ERROR_BASE = error_mod.CUSTOM_ERROR_BASE;

/// Create custom error code
pub const customErrorCode = error_mod.customErrorCode;

// ============================================================================
// IDL Generation
// ============================================================================

/// IDL generation for zero_cu programs (recommended)
///
/// ```zig
/// const idl = anchor.idl_zero;
///
/// pub const Program = struct {
///     pub const id = sol.PublicKey.comptimeFromBase58("...");
///     pub const name = "counter";
///     pub const version = "0.1.0";
///
///     pub const instructions = .{
///         idl.Instruction("increment", IncrementAccounts, void),
///     };
///
///     pub const accounts = .{
///         idl.AccountDef("Counter", CounterData),
///     };
/// };
///
/// // Generate IDL
/// const json = try idl.generateJson(allocator, Program);
/// ```
pub const idl_zero = @import("idl_zero.zig");

/// IDL instruction definition
pub const IdlInstruction = idl_zero.Instruction;

/// IDL account definition
pub const IdlAccountDef = idl_zero.AccountDef;

/// IDL event definition
pub const IdlEventDef = idl_zero.EventDef;

/// Generate IDL JSON for zero_cu program
pub const generateIdlZero = idl_zero.generateJson;

/// Write IDL JSON to file
pub const writeIdlFile = idl_zero.writeJsonFile;

/// Anchor IDL generation utilities (standard API, legacy)
pub const idl = @import("idl.zig");

/// Zig client code generation utilities
pub const codegen = @import("codegen.zig");

/// IDL config overrides (standard API)
pub const IdlConfig = idl.IdlConfig;

/// Instruction descriptor for IDL/codegen
pub const Instruction = idl.Instruction;

/// Generate Anchor-compatible IDL JSON
pub const generateIdlJson = idl.generateJson;

/// Generate Zig client module source
pub const generateZigClient = codegen.generateZigClient;

// ============================================================================
// AccountLoader (Zero-Copy) - Advanced
// ============================================================================

/// AccountLoader for zero-copy account access
pub const account_loader = @import("account_loader.zig");

/// AccountLoader config
pub const AccountLoaderConfig = account_loader.AccountLoaderConfig;

/// Zero-copy account loader type
pub const AccountLoader = account_loader.AccountLoader;

// ============================================================================
// LazyAccount - Advanced
// ============================================================================

/// LazyAccount for on-demand deserialization
pub const lazy_account = @import("lazy_account.zig");

/// LazyAccount config
pub const LazyAccountConfig = lazy_account.LazyAccountConfig;

/// LazyAccount type
pub const LazyAccount = lazy_account.LazyAccount;

// ============================================================================
// Program Entry (Standard API)
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
// Optimized Entry Point (Standard API)
// ============================================================================

/// Optimized entry point with tiered validation
/// 
/// Note: For best performance, use zero_cu instead.
pub const optimized = @import("optimized.zig");

/// Validation level for optimized entry
pub const ValidationLevel = optimized.ValidationLevel;

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
// SPL Memo/Stake Helpers
// ============================================================================

/// SPL Memo CPI helpers
pub const memo = @import("memo.zig");

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
pub const emitEvent = event.emitEvent;

/// Emit an event with a custom discriminator
pub const emitEventWithDiscriminator = event.emitEventWithDiscriminator;

/// Get the discriminator for an event type
pub const getEventDiscriminator = event.getEventDiscriminator;

// ============================================================================
// Type-Safe DSL (Advanced)
// ============================================================================

/// Type-Safe DSL for Solana Program Development
///
/// For advanced users who need complex validation patterns.
/// For simple programs, use zero_cu instead.
pub const dsl = @import("typed_dsl.zig");

// ============================================================================
// Constraints Module (Standard API)
// ============================================================================

/// Constraint types and validation
pub const constraints = @import("constraints.zig");

/// Constraint specification for account validation
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
// Account Module (Standard API)
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

/// Account wrapper type (Standard API)
///
/// Note: For best performance, use zero_cu.Account instead.
pub const Account = account.Account;

/// Account wrapper with field-level attrs.
pub const AccountField = account.AccountField;

/// Account loading errors
pub const AccountError = account.AccountError;

// ============================================================================
// Signer Module (Standard API)
// ============================================================================

/// Signer account types
pub const signer = @import("signer.zig");

/// Signer account type (read-only) - Standard API
///
/// Note: For best performance, use zero_cu.Signer instead.
pub const Signer = signer.Signer;

/// Mutable signer account type - Standard API
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
pub const Program = program.Program;

/// Unchecked program reference
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
// Context Module (Standard API)
// ============================================================================

/// Instruction context types
pub const context = @import("context.zig");

/// Instruction context (Standard API)
///
/// Note: For best performance, use zero_cu.Ctx instead.
pub const Context = context.Context;

/// Bump seeds storage
pub const Bumps = context.Bumps;

/// Load accounts from account info slice
pub const loadAccounts = context.loadAccounts;

/// Parse full context from program inputs
pub const parseContext = context.parseContext;

/// Load accounts with dependency resolution for non-literal seeds
pub const loadAccountsWithDependencies = context.loadAccountsWithDependencies;

/// Context loading errors
pub const ContextError = context.ContextError;

/// Convert a slice of accounts into a slice of Account.Info using a caller-provided buffer.
pub fn accountsToInfoSlice(accounts: anytype, out: []sdk.account.Account.Info) []const sdk.account.Account.Info {
    const AccountsType = @TypeOf(accounts);
    const info = @typeInfo(AccountsType);
    if (info != .pointer or info.pointer.size != .slice) {
        @compileError("accountsToInfoSlice expects a slice");
    }
    const Child = info.pointer.child;
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
// Seeds Module
// ============================================================================

/// Seed types for PDA derivation
pub const seeds = @import("seeds.zig");

/// Seed specification type
pub const SeedSpec = seeds.SeedSpec;

/// Create a literal seed
pub const seed = seeds.seed;

/// Create an account reference seed
pub const seedAccount = seeds.seedAccount;

/// Create an account reference seed using typed field selector.
pub fn seedAccountField(comptime AccountsType: type, comptime field: std.meta.FieldEnum(AccountsType)) SeedSpec {
    return seeds.seedAccount(accountField(AccountsType, field));
}

/// Create a field reference seed
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
// PDA Module
// ============================================================================

/// PDA validation and derivation utilities
pub const pda = @import("pda.zig");

/// Validate that an account matches the expected PDA
pub const validatePda = pda.validatePda;

/// Validate PDA using runtime-resolved seeds (slice-based)
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
// Init Module
// ============================================================================

/// Account initialization utilities
pub const init = @import("init.zig");

/// Configuration for account initialization
pub const InitConfig = init.InitConfig;

/// Configuration for batch account initialization
pub const BatchInitConfig = init.BatchInitConfig;

/// Get rent-exempt balance for an account
pub const rentExemptBalance = init.rentExemptBalance;

/// Calculate rent-exempt balance using defaults
pub const rentExemptBalanceDefault = init.rentExemptBalanceDefault;

/// Create a new account via CPI
pub const createAccount = init.createAccount;

/// Create multiple accounts via CPI
pub const createAccounts = init.createAccounts;

/// Create an account at a PDA via CPI
pub const createAccountAtPda = init.createAccountAtPda;

/// Check if an account is uninitialized
pub const isUninitialized = init.isUninitialized;

/// Validate account is ready for initialization
pub const validateForInit = init.validateForInit;

/// Account initialization errors
pub const InitError = init.InitError;

// ============================================================================
// Has-One Module
// ============================================================================

/// Has-one constraint validation
pub const has_one = @import("has_one.zig");

/// Has-one constraint specification
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
// Close Module
// ============================================================================

/// Account closing utilities
pub const close = @import("close.zig");

/// Close an account, transferring lamports to destination
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
// Realloc Module
// ============================================================================

/// Account reallocation utilities
pub const realloc = @import("realloc.zig");

/// Maximum account size (10 MB)
pub const MAX_ACCOUNT_SIZE = realloc.MAX_ACCOUNT_SIZE;

/// Realloc configuration
pub const ReallocConfig = realloc.ReallocConfig;

/// Reallocate account data to new size
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
// Zero Program (Alias)
// ============================================================================

/// Alias for zero_cu (same module)
pub const zero_program = @import("zero_program.zig");

// ============================================================================
// Tests
// ============================================================================

test "anchor module exports" {
    // zero_cu (recommended)
    _ = zero_cu;
    _ = zero_cu.Signer;
    _ = zero_cu.Mut;
    _ = zero_cu.Readonly;
    _ = zero_cu.Account;
    _ = zero_cu.Ctx;
    _ = zero_cu.entry;
    _ = zero_cu.multi;
    _ = zero_cu.inst;
    
    // Discriminator
    _ = DISCRIMINATOR_LENGTH;
    _ = Discriminator;
    _ = accountDiscriminator;
    _ = instructionDiscriminator;
    
    // Error
    _ = AnchorError;
    
    // Standard API (legacy)
    _ = Account;
    _ = Signer;
    _ = SignerMut;
    _ = Context;
    _ = Constraints;
    
    // SPL helpers
    _ = token;
    _ = associated_token;
    _ = memo;
    _ = stake;
    _ = TokenAccount;
    _ = Mint;
    
    // PDA helpers
    _ = seed;
    _ = seedAccount;
    _ = validatePda;
    
    // Init/Close helpers
    _ = rentExemptBalance;
    _ = createAccount;
    _ = closeAccount;
    _ = reallocAccount;
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

test "seeds submodule" {
    _ = seeds;
}

test "pda submodule" {
    _ = pda;
}

test "init submodule" {
    _ = init;
}

test "has_one submodule" {
    _ = has_one;
}

test "close submodule" {
    _ = close;
}

test "realloc submodule" {
    _ = realloc;
}

test "zero_cu submodule" {
    _ = zero_cu;
}
