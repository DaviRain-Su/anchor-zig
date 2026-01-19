//! sol-anchor-zig: High-Performance Anchor Framework for Zig
//!
//! ## zero_cu API (5-7 CU) - Recommended
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
//! ## Performance
//!
//! The zero_cu API achieves 5-7 CU overhead per instruction by:
//! - Zero-copy account parsing
//! - Compile-time constraint validation
//! - Optimized discriminator checking
//!
//! ## SPL Program Integrations
//!
//! ```zig
//! const spl = anchor.spl;
//!
//! const TransferAccounts = struct {
//!     source: spl.token.TokenAccount(.{ .mut = true }),
//!     destination: spl.token.TokenAccount(.{ .mut = true }),
//!     authority: zero.Signer(0),
//!     token_program: spl.token.Program,
//! };
//! ```

const std = @import("std");

/// Re-export solana_program_sdk for convenience.
pub const sdk = @import("solana_program_sdk");

// ============================================================================
// Zero-CU Framework (5-7 CU) - Recommended
// ============================================================================

/// Zero-CU Framework - High-level API with minimal runtime overhead
///
/// ## Account Types
/// - `zero.Signer(size)` - Signer account
/// - `zero.Mut(T)` - Mutable account with typed data
/// - `zero.Readonly(T)` - Readonly account
/// - `zero.Account(T, .{...})` - Account with constraints
/// - `zero.Program(id)` - Program account
/// - `zero.Optional(T)` - Optional account
/// - `zero.UncheckedAccount(size)` - Unchecked account
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
/// - `zero.createPdaAccount(...)` - Create PDA account
/// - `zero.closeAccount(...)` - Close account
/// - `zero.transferLamports(...)` - Transfer lamports
/// - `zero.allocate(...)` - Allocate space
pub const zero_cu = @import("zero_cu.zig");

// Convenient re-exports from zero_cu
pub const Signer = zero_cu.Signer;
pub const Mut = zero_cu.Mut;
pub const Readonly = zero_cu.Readonly;
pub const ZeroAccount = zero_cu.Account;
pub const Program = zero_cu.Program;
pub const Optional = zero_cu.Optional;
pub const UncheckedAccount = zero_cu.UncheckedAccount;
pub const Ctx = zero_cu.Ctx;
pub const AccountConstraints = zero_cu.AccountConstraints;
pub const Seed = zero_cu.Seed;
pub const seed = zero_cu.seed;
pub const seedAccount = zero_cu.seedAccount;
pub const seedField = zero_cu.seedField;

// ============================================================================
// Discriminator Module
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

/// IDL generation for zero_cu programs
///
/// ```zig
/// const idl = anchor.idl_zero;
///
/// pub const ProgramDef = struct {
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
/// const json = try idl.generateJson(allocator, ProgramDef);
/// ```
pub const idl_zero = @import("idl_zero.zig");

/// IDL instruction definition
pub const IdlInstruction = idl_zero.Instruction;

/// IDL instruction definition with docs
pub const IdlInstructionWithDocs = idl_zero.InstructionWithDocs;

/// IDL account definition
pub const IdlAccountDef = idl_zero.AccountDef;

/// IDL account definition with docs
pub const IdlAccountDefWithDocs = idl_zero.AccountDefWithDocs;

/// IDL event definition
pub const IdlEventDef = idl_zero.EventDef;

/// Generate IDL JSON for zero_cu program
pub const generateIdlJson = idl_zero.generateJson;

/// Write IDL JSON to file
pub const writeIdlFile = idl_zero.writeJsonFile;

// ============================================================================
// SPL Program Integrations
// ============================================================================

/// SPL Program Integrations
///
/// Provides Anchor-style wrappers for SPL programs:
/// - `spl.token`: Token program (TokenAccount, MintAccount, Program, CPI helpers)
///
/// Usage:
/// ```zig
/// const anchor = @import("sol_anchor_zig");
/// const spl = anchor.spl;
///
/// const Accounts = struct {
///     source: spl.token.TokenAccount(.{ .mut = true }),
///     destination: spl.token.TokenAccount(.{ .mut = true }),
///     authority: anchor.zero_cu.Signer(0),
///     token_program: spl.token.Program,
/// };
/// ```
pub const spl = @import("spl/root.zig");

/// SPL Associated Token Account CPI helpers
pub const associated_token = @import("associated_token.zig");

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
// System/Sysvar Account Helpers
// ============================================================================

/// System account wrappers
pub const system_account = @import("system_account.zig");

/// System-owned account (read-only)
pub const SystemAccount = system_account.SystemAccountConst;

/// System-owned account (mutable)
pub const SystemAccountMut = system_account.SystemAccountMut;

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
// CPI Helpers (from zero_cu)
// ============================================================================

/// Close an account, transferring lamports to destination
pub const closeAccount = zero_cu.closeAccount;

/// Create a new account via CPI
pub const createAccount = zero_cu.createAccount;

/// Create a PDA account via CPI
pub const createPdaAccount = zero_cu.createPdaAccount;

/// Transfer lamports between accounts
pub const transferLamports = zero_cu.transferLamports;

/// Allocate space for a PDA account
pub const allocate = zero_cu.allocate;

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

    // SPL helpers
    _ = spl;
    _ = associated_token;
    _ = memo;
    _ = stake;

    // System/Sysvar
    _ = system_account;
    _ = sysvar_account;

    // CPI helpers
    _ = closeAccount;
    _ = createAccount;
    _ = transferLamports;
}

test "discriminator submodule" {
    _ = discriminator;
}

test "error submodule" {
    _ = error_mod;
}

test "zero_cu submodule" {
    _ = zero_cu;
}

test "event submodule" {
    _ = event;
}

test "idl_zero submodule" {
    _ = idl_zero;
}
