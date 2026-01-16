//! Zig implementation of Anchor error codes
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/error.rs
//!
//! Error codes are compatible with Anchor for client interoperability.
//! The error code ranges match Anchor exactly:
//! - Instruction errors: 100-199
//! - IDL errors: 1000-1999 (not implemented in Phase 1)
//! - Constraint errors: 2000-2999
//! - Account errors: 3000-3999
//! - Misc errors: 4100-4999 (not implemented in Phase 1)
//! - Deprecated errors: 5000-5999 (not implemented)
//! - Custom errors: 6000+ (user-defined)

const std = @import("std");

/// Anchor framework errors
///
/// Uses same error codes as Rust Anchor for client compatibility.
/// Clients can decode these error codes to display meaningful messages.
pub const AnchorError = enum(u32) {
    // ========================================================================
    // Instruction errors (100-199)
    // ========================================================================

    /// 100 - 8-byte instruction identifier not found in first 8 bytes of data
    InstructionMissing = 100,

    /// 101 - Fallback functions are not supported
    InstructionFallbackNotFound = 101,

    /// 102 - Instruction data could not be deserialized
    InstructionDidNotDeserialize = 102,

    /// 103 - Instruction data could not be serialized
    InstructionDidNotSerialize = 103,

    // ========================================================================
    // Constraint errors (2000-2999)
    // ========================================================================

    /// 2000 - A mut constraint was violated (account not writable)
    ConstraintMut = 2000,

    /// 2001 - A has_one constraint was violated (field mismatch)
    ConstraintHasOne = 2001,

    /// 2002 - A signer constraint was violated (account not signer)
    ConstraintSigner = 2002,

    /// 2003 - A raw constraint expression evaluated to false
    ConstraintRaw = 2003,

    /// 2004 - An owner constraint was violated (wrong program owner)
    ConstraintOwner = 2004,

    /// 2005 - An address constraint was violated (wrong pubkey)
    ConstraintAddress = 2005,

    /// 2006 - A seeds constraint was violated (PDA mismatch)
    ConstraintSeeds = 2006,

    /// 2007 - An executable constraint was violated (account not executable)
    ConstraintExecutable = 2007,

    /// 2008 - Deprecated - state not supported
    ConstraintState = 2008,

    /// 2009 - An associated constraint was violated
    ConstraintAssociated = 2009,

    /// 2010 - An associated init constraint was violated
    ConstraintAssociatedInit = 2010,

    /// 2011 - A close constraint was violated
    ConstraintClose = 2011,

    /// 2012 - A rent exempt constraint was violated
    ConstraintRentExempt = 2012,

    /// 2013 - A zero constraint was violated (account not zeroed)
    ConstraintZero = 2013,

    /// 2014 - A token mint constraint was violated
    ConstraintTokenMint = 2014,

    /// 2015 - A token owner constraint was violated
    ConstraintTokenOwner = 2015,

    /// 2016 - A mint mint authority constraint was violated
    ConstraintMintMintAuthority = 2016,

    /// 2017 - A mint freeze authority constraint was violated
    ConstraintMintFreezeAuthority = 2017,

    /// 2018 - A mint decimals constraint was violated
    ConstraintMintDecimals = 2018,

    /// 2019 - A space constraint was violated
    ConstraintSpace = 2019,

    /// 2020 - A required account is not owned by this program
    ConstraintAccountIsNone = 2020,

    /// 2040 - A duplicate mutable account constraint was violated
    ConstraintDuplicateMutableAccount = 2040,

    // ========================================================================
    // Account errors (3000-3999)
    // ========================================================================

    /// 3000 - Account discriminator did not match expected value
    AccountDiscriminatorMismatch = 3000,

    /// 3001 - Account discriminator was not found (account too small)
    AccountDiscriminatorNotFound = 3001,

    /// 3002 - Account was not initialized
    AccountNotInitialized = 3002,

    /// 3003 - Account is not a program data account
    AccountNotProgramData = 3003,

    /// 3004 - Account is not an associated token account
    AccountNotAssociatedTokenAccount = 3004,

    /// 3005 - Account is owned by wrong program
    AccountOwnedByWrongProgram = 3005,

    /// 3006 - Invalid program id
    InvalidProgramId = 3006,

    /// 3007 - Invalid program executable
    InvalidProgramExecutable = 3007,

    /// 3008 - Account data could not be deserialized
    AccountDidNotDeserialize = 3008,

    /// 3009 - Account data could not be serialized
    AccountDidNotSerialize = 3009,

    /// 3010 - Account is not owned by system program
    AccountNotSystemOwned = 3010,

    /// 3011 - Account has duplicate reallocations
    AccountDuplicateReallocs = 3011,

    /// 3012 - Account reallocation exceeds limit
    AccountReallocExceedsLimit = 3012,

    /// 3013 - Account is not a sysvar
    AccountSysvarMismatch = 3013,

    /// 3014 - Not enough accounts provided
    AccountNotEnoughAccountKeys = 3014,

    /// 3015 - Program not rent exempt
    AccountNotRentExempt = 3015,

    /// Convert to u32 for syscall return or client communication
    pub fn toU32(self: AnchorError) u32 {
        return @intFromEnum(self);
    }

    /// Convert from u32 error code
    pub fn fromU32(code: u32) ?AnchorError {
        return std.meta.intToEnum(AnchorError, code) catch null;
    }

    /// Get human-readable error message
    pub fn message(self: AnchorError) []const u8 {
        return switch (self) {
            .InstructionMissing => "8-byte instruction identifier not found",
            .InstructionFallbackNotFound => "Fallback functions are not supported",
            .InstructionDidNotDeserialize => "Instruction data could not be deserialized",
            .InstructionDidNotSerialize => "Instruction data could not be serialized",
            .ConstraintMut => "A mut constraint was violated",
            .ConstraintHasOne => "A has_one constraint was violated",
            .ConstraintSigner => "A signer constraint was violated",
            .ConstraintRaw => "A raw constraint was violated",
            .ConstraintOwner => "An owner constraint was violated",
            .ConstraintAddress => "An address constraint was violated",
            .ConstraintSeeds => "A seeds constraint was violated",
            .ConstraintExecutable => "An executable constraint was violated",
            .ConstraintState => "Deprecated state constraint",
            .ConstraintAssociated => "An associated constraint was violated",
            .ConstraintAssociatedInit => "An associated init constraint was violated",
            .ConstraintClose => "A close constraint was violated",
            .ConstraintRentExempt => "A rent exempt constraint was violated",
            .ConstraintZero => "A zero constraint was violated",
            .ConstraintTokenMint => "A token mint constraint was violated",
            .ConstraintTokenOwner => "A token owner constraint was violated",
            .ConstraintMintMintAuthority => "A mint mint authority constraint was violated",
            .ConstraintMintFreezeAuthority => "A mint freeze authority constraint was violated",
            .ConstraintMintDecimals => "A mint decimals constraint was violated",
            .ConstraintSpace => "A space constraint was violated",
            .ConstraintAccountIsNone => "A required account is not owned by this program",
            .ConstraintDuplicateMutableAccount => "A duplicate mutable account constraint was violated",
            .AccountDiscriminatorMismatch => "Account discriminator did not match",
            .AccountDiscriminatorNotFound => "Account discriminator not found",
            .AccountNotInitialized => "Account was not initialized",
            .AccountNotProgramData => "Account is not a program data account",
            .AccountNotAssociatedTokenAccount => "Account is not an associated token account",
            .AccountOwnedByWrongProgram => "Account is owned by wrong program",
            .InvalidProgramId => "Invalid program id",
            .InvalidProgramExecutable => "Invalid program executable",
            .AccountDidNotDeserialize => "Account data could not be deserialized",
            .AccountDidNotSerialize => "Account data could not be serialized",
            .AccountNotSystemOwned => "Account is not owned by system program",
            .AccountDuplicateReallocs => "Account has duplicate reallocations",
            .AccountReallocExceedsLimit => "Account reallocation exceeds limit",
            .AccountSysvarMismatch => "Account is not expected sysvar",
            .AccountNotEnoughAccountKeys => "Not enough account keys provided",
            .AccountNotRentExempt => "Program not rent exempt",
        };
    }
};

/// Custom error base (user errors start at 6000 like Anchor)
pub const CUSTOM_ERROR_BASE: u32 = 6000;

/// Helper to create custom error codes
///
/// Usage:
/// ```zig
/// const MyError = enum(u32) {
///     InvalidAmount = customErrorCode(0),  // 6000
///     Unauthorized = customErrorCode(1),   // 6001
/// };
/// ```
pub fn customErrorCode(offset: u32) u32 {
    return CUSTOM_ERROR_BASE + offset;
}

// ============================================================================
// Tests
// ============================================================================

test "AnchorError codes match Anchor" {
    // Verify key error codes match Anchor exactly
    try std.testing.expectEqual(@as(u32, 100), AnchorError.InstructionMissing.toU32());
    try std.testing.expectEqual(@as(u32, 2000), AnchorError.ConstraintMut.toU32());
    try std.testing.expectEqual(@as(u32, 2002), AnchorError.ConstraintSigner.toU32());
    try std.testing.expectEqual(@as(u32, 2004), AnchorError.ConstraintOwner.toU32());
    try std.testing.expectEqual(@as(u32, 3000), AnchorError.AccountDiscriminatorMismatch.toU32());
    try std.testing.expectEqual(@as(u32, 3001), AnchorError.AccountDiscriminatorNotFound.toU32());
}

test "AnchorError fromU32 conversion" {
    const err = AnchorError.fromU32(2002);
    try std.testing.expectEqual(AnchorError.ConstraintSigner, err.?);

    const invalid = AnchorError.fromU32(99999);
    try std.testing.expect(invalid == null);
}

test "AnchorError message returns string" {
    const msg = AnchorError.ConstraintSigner.message();
    try std.testing.expect(msg.len > 0);
    try std.testing.expectEqualStrings("A signer constraint was violated", msg);
}

test "customErrorCode starts at 6000" {
    try std.testing.expectEqual(@as(u32, 6000), customErrorCode(0));
    try std.testing.expectEqual(@as(u32, 6001), customErrorCode(1));
    try std.testing.expectEqual(@as(u32, 6100), customErrorCode(100));
}
