//! Anchor IDL example program module
//!
//! Rust source: https://github.com/coral-xyz/anchor/blob/master/lang/syn/src/idl.rs
//!
//! This module exposes an example program definition for IDL generation.

const anchor = @import("sol_anchor_zig");

pub const Program = anchor.idl.ExampleProgram;
