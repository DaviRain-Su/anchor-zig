//! Zero-CU Program Module
//!
//! Re-exports zero_cu types for convenient access via `anchor.zero_program`.
//!
//! ## Usage
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const zero = anchor.zero_program;  // or anchor.zero_cu
//!
//! const MyAccounts = struct {
//!     source: zero.Signer(0),
//!     dest: zero.Mut(0),
//! };
//!
//! pub const Program = struct {
//!     pub const id = anchor.sdk.PublicKey.comptimeFromBase58("...");
//!
//!     pub fn transfer(ctx: zero.Ctx(MyAccounts)) !void {
//!         const source = ctx.accounts.source;
//!         const dest = ctx.accounts.dest;
//!         // ...
//!     }
//! };
//!
//! // Single instruction (5 CU)
//! comptime {
//!     zero.entry(MyAccounts, "transfer", Program.transfer);
//! }
//!
//! // Multi instruction (7 CU each)
//! comptime {
//!     zero.multi(SharedAccounts, .{
//!         zero.inst("initialize", Program.initialize),
//!         zero.inst("transfer", Program.transfer),
//!     });
//! }
//! ```

const zero_cu = @import("zero_cu.zig");

// ============================================================================
// Account Type Markers
// ============================================================================

/// Signer account with data size
pub const Signer = zero_cu.Signer;
pub const ZeroSigner = zero_cu.Signer;

/// Mutable (writable) account with data size
pub const Mut = zero_cu.Mut;
pub const ZeroMut = zero_cu.Mut;

/// Readonly account with data size
pub const Readonly = zero_cu.Readonly;
pub const ZeroReadonly = zero_cu.Readonly;

// ============================================================================
// Context Types
// ============================================================================

/// Instruction context with named account access
pub const Ctx = zero_cu.Ctx;
pub const Context = zero_cu.Ctx;
pub const ZeroInstructionContext = zero_cu.ZeroInstructionContext;

// ============================================================================
// Entrypoint Generators
// ============================================================================

/// Export single-instruction entrypoint (5 CU)
pub const entry = zero_cu.entry;
pub const exportSingleInstruction = zero_cu.entry;

/// Create instruction with precomputed discriminator
pub const inst = zero_cu.inst;
pub const instruction = zero_cu.instruction;

/// Export multi-instruction entrypoint (7 CU each)
pub const multi = zero_cu.multi;
pub const exportMultiInstruction = zero_cu.multi;

// ============================================================================
// Utilities
// ============================================================================

/// Calculate account data lengths from struct
pub const accountDataLengths = zero_cu.accountDataLengths;

/// Calculate instruction data offset
pub const instructionDataOffset = zero_cu.instructionDataOffset;

/// Calculate account size in buffer
pub const accountSize = zero_cu.accountSize;

/// Low-level account accessor
pub const ZeroAccount = zero_cu.ZeroAccount;

/// Legacy context type
pub const ZeroContext = zero_cu.ZeroContext;
