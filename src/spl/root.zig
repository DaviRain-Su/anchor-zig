//! anchor-zig SPL Program Integrations
//!
//! Provides Anchor-style wrappers for Solana Program Library (SPL) programs.
//!
//! ## Available Modules
//!
//! - `token`: SPL Token Program integration
//!   - Account types: `TokenAccount`, `MintAccount`, `Program`
//!   - CPI helpers: `transferCpi`, `mintToCpi`, `burnCpi`, `closeAccountCpi`
//!
//! ## Usage
//!
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//! const spl = anchor.spl;
//!
//! const Accounts = struct {
//!     source: spl.token.TokenAccount(.{ .mut = true }),
//!     destination: spl.token.TokenAccount(.{ .mut = true }),
//!     authority: anchor.zero_cu.Signer(0),
//!     token_program: spl.token.Program,
//! };
//! ```

pub const token = @import("token.zig");
