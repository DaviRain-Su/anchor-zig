//! Anchor-style SPL Associated Token Account helpers.
//!
//! Rust source: https://github.com/solana-program/associated-token-account/blob/master/interface/src/instruction.rs

const sol = @import("solana_program_sdk");

const AccountInfo = sol.account.Account.Info;
const AccountMeta = sol.instruction.AccountMeta;
const AccountParam = sol.account.Account.Param;
const Instruction = sol.instruction.Instruction;
const PublicKey = sol.PublicKey;

/// Associated Token Account Program ID.
pub const ASSOCIATED_TOKEN_PROGRAM_ID = PublicKey.comptimeFromBase58("ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL");

/// Associated Token program instruction tags.
const AssociatedTokenInstruction = enum(u8) {
    Create = 0,
    CreateIdempotent = 1,
};

/// CPI helper errors.
pub const AssociatedTokenCpiError = union(enum) {
    InvokeFailed,
    InvokeFailedWithCode: u64,
};

/// Batch associated token init configuration.
pub const BatchInitConfig = struct {
    associated_token_program: *const AccountInfo,
    payer: *const AccountInfo,
    associated_token_account: *const AccountInfo,
    authority: *const AccountInfo,
    mint: *const AccountInfo,
    system_program: *const AccountInfo,
    token_program: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8 = null,
};

fn invokeInstruction(
    ix: *const Instruction,
    infos: []const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) ?AssociatedTokenCpiError {
    const result = if (signer_seeds) |seeds|
        ix.invokeSigned(infos, seeds)
    else
        ix.invoke(infos);
    if (result != null) {
        return .{ .InvokeFailedWithCode = result.?.toU64() };
    }
    return null;
}

fn buildParams(comptime N: usize, metas: *const [N]AccountMeta) [N]AccountParam {
    var params: [N]AccountParam = undefined;
    inline for (metas.*, 0..) |*meta, i| {
        params[i] = sol.instruction.accountMetaToParam(meta);
    }
    return params;
}

/// Create an associated token account (fails if already exists).
pub fn create(
    associated_token_program: *const AccountInfo,
    payer: *const AccountInfo,
    associated_token_account: *const AccountInfo,
    authority: *const AccountInfo,
    mint: *const AccountInfo,
    system_program: *const AccountInfo,
    token_program: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) ?AssociatedTokenCpiError {
    const data = [1]u8{ @intFromEnum(AssociatedTokenInstruction.Create) };
    var metas = [_]AccountMeta{
        AccountMeta.newWritableSigner(payer.id.*),
        AccountMeta.newWritable(associated_token_account.id.*),
        AccountMeta.newReadonly(authority.id.*),
        AccountMeta.newReadonly(mint.id.*),
        AccountMeta.newReadonly(system_program.id.*),
        AccountMeta.newReadonly(token_program.id.*),
    };
    const params = buildParams(6, &metas);
    const ix = Instruction.from(.{
        .program_id = associated_token_program.id,
        .accounts = params[0..],
        .data = data[0..],
    });
    const infos = [_]AccountInfo{
        payer.*,
        associated_token_account.*,
        authority.*,
        mint.*,
        system_program.*,
        token_program.*,
    };
    return invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Create an associated token account if needed (idempotent).
pub fn createIdempotent(
    associated_token_program: *const AccountInfo,
    payer: *const AccountInfo,
    associated_token_account: *const AccountInfo,
    authority: *const AccountInfo,
    mint: *const AccountInfo,
    system_program: *const AccountInfo,
    token_program: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) ?AssociatedTokenCpiError {
    const data = [1]u8{ @intFromEnum(AssociatedTokenInstruction.CreateIdempotent) };
    var metas = [_]AccountMeta{
        AccountMeta.newWritableSigner(payer.id.*),
        AccountMeta.newWritable(associated_token_account.id.*),
        AccountMeta.newReadonly(authority.id.*),
        AccountMeta.newReadonly(mint.id.*),
        AccountMeta.newReadonly(system_program.id.*),
        AccountMeta.newReadonly(token_program.id.*),
    };
    const params = buildParams(6, &metas);
    const ix = Instruction.from(.{
        .program_id = associated_token_program.id,
        .accounts = params[0..],
        .data = data[0..],
    });
    const infos = [_]AccountInfo{
        payer.*,
        associated_token_account.*,
        authority.*,
        mint.*,
        system_program.*,
        token_program.*,
    };
    return invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Create multiple associated token accounts (idempotent).
pub fn createBatchIdempotent(configs: []const BatchInitConfig) ?AssociatedTokenCpiError {
    for (configs) |cfg| {
        if (createIdempotent(
            cfg.associated_token_program,
            cfg.payer,
            cfg.associated_token_account,
            cfg.authority,
            cfg.mint,
            cfg.system_program,
            cfg.token_program,
            cfg.signer_seeds,
        )) |err| {
            return err;
        }
    }
    return null;
}
