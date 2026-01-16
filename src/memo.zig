//! Anchor-style SPL Memo CPI helpers.
//!
//! Rust sources:
//! - https://github.com/solana-program/memo/blob/master/interface/src/lib.rs
//! - https://github.com/solana-program/memo/blob/master/interface/src/instruction.rs

const std = @import("std");
const sol = @import("solana_program_sdk");

const AccountInfo = sol.account.Account.Info;
const AccountMeta = sol.instruction.AccountMeta;
const AccountParam = sol.account.Account.Param;
const Instruction = sol.instruction.Instruction;

const memo_mod = sol.spl.memo;

/// SPL Memo program id (v2/v3).
pub const MEMO_PROGRAM_ID = memo_mod.MEMO_PROGRAM_ID;

/// SPL Memo v1 program id (legacy).
pub const MEMO_V1_PROGRAM_ID = memo_mod.MEMO_V1_PROGRAM_ID;

/// CPI helper errors.
pub const MemoCpiError = error{
    InvokeFailed,
    InvalidUtf8,
};

fn invokeInstruction(
    ix: *const Instruction,
    infos: []const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) MemoCpiError!void {
    const result = if (signer_seeds) |seeds|
        ix.invokeSigned(infos, seeds)
    else
        ix.invoke(infos);
    if (result != null) {
        return MemoCpiError.InvokeFailed;
    }
}

fn buildParams(comptime N: usize, metas: *const [N]AccountMeta) [N]AccountParam {
    var params: [N]AccountParam = undefined;
    inline for (metas.*, 0..) |*meta, i| {
        params[i] = sol.instruction.accountMetaToParam(meta);
    }
    return params;
}

fn buildAccountInfos(comptime N: usize, signer_infos: *const [N]*const AccountInfo) [N]AccountInfo {
    var infos: [N]AccountInfo = undefined;
    inline for (signer_infos.*, 0..) |signer, i| {
        infos[i] = signer.*;
    }
    return infos;
}

/// Invoke the Memo program with optional signer accounts (no UTF-8 validation).
pub fn memo(
    comptime N: usize,
    memo_program: *const AccountInfo,
    signer_infos: *const [N]*const AccountInfo,
    memo_text: []const u8,
    signer_seeds: ?[]const []const []const u8,
) MemoCpiError!void {
    var metas: [N]AccountMeta = undefined;
    inline for (signer_infos.*, 0..) |signer, i| {
        metas[i] = AccountMeta.newReadonlySigner(signer.id.*);
    }

    const params = buildParams(N, &metas);
    const ix = Instruction.from(.{
        .program_id = memo_program.id,
        .accounts = params[0..],
        .data = memo_text,
    });
    const infos = buildAccountInfos(N, signer_infos);
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke the Memo program with UTF-8 validation before issuing CPI.
pub fn memoValidated(
    comptime N: usize,
    memo_program: *const AccountInfo,
    signer_infos: *const [N]*const AccountInfo,
    memo_text: []const u8,
    signer_seeds: ?[]const []const []const u8,
) MemoCpiError!void {
    if (!memo_mod.isValidUtf8(memo_text)) {
        return MemoCpiError.InvalidUtf8;
    }
    return memo(N, memo_program, signer_infos, memo_text, signer_seeds);
}

test "memo: validated rejects invalid utf8" {
    var program_id = MEMO_PROGRAM_ID;
    var owner = MEMO_PROGRAM_ID;
    var lamports: u64 = 0;
    var data: [0]u8 = undefined;
    const memo_program = AccountInfo{
        .id = &program_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 1,
        .rent_epoch = 0,
    };
    const invalid = &[_]u8{ 0xC0, 0x00 };
    try std.testing.expectError(
        MemoCpiError.InvalidUtf8,
        memoValidated(0, &memo_program, &[_]*const AccountInfo{}, invalid, null),
    );
}
