//! Anchor-style SPL Stake helpers and wrappers.
//!
//! Rust sources:
//! - https://github.com/solana-program/stake/blob/master/interface/src/state.rs
//! - https://github.com/solana-program/stake/blob/master/interface/src/instruction.rs

const sol = @import("solana_program_sdk");

const AccountInfo = sol.account.Account.Info;
const AccountMeta = sol.instruction.AccountMeta;
const AccountParam = sol.account.Account.Param;
const Instruction = sol.instruction.Instruction;
const PublicKey = sol.PublicKey;

const stake_mod = sol.spl.stake;
const stake_instruction = stake_mod.instruction;
const stake_state = stake_mod.state;

/// Stake program id.
pub const STAKE_PROGRAM_ID = stake_mod.STAKE_PROGRAM_ID;

/// Stake config program id (deprecated but still required by delegate/redelegate).
pub const STAKE_CONFIG_PROGRAM_ID = stake_mod.STAKE_CONFIG_PROGRAM_ID;

/// CPI helper errors.
pub const StakeCpiError = error{
    InvokeFailed,
};

fn invokeInstruction(
    ix: *const Instruction,
    infos: []const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const result = if (signer_seeds) |seeds|
        ix.invokeSigned(infos, seeds)
    else
        ix.invoke(infos);
    if (result != null) {
        return StakeCpiError.InvokeFailed;
    }
}

fn buildParams(comptime N: usize, metas: *const [N]AccountMeta) [N]AccountParam {
    var params: [N]AccountParam = undefined;
    inline for (metas.*, 0..) |_, i| {
        params[i] = sol.instruction.accountMetaToParam(&metas.*[i]);
    }
    return params;
}

// ============================================================================
// StakeAccount Wrapper
// ============================================================================

/// Stake account wrapper configuration.
pub const StakeAccountConfig = struct {
    address: ?PublicKey = null,
    mut: bool = false,
    signer: bool = false,
};

/// Stake account wrapper.
pub fn StakeAccount(comptime config: StakeAccountConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,
        data: stake_state.StakeStateV2,

        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        /// Load and validate a stake account from AccountInfo.
        pub fn load(info: *const AccountInfo) !Self {
            if (!info.owner_id.equals(STAKE_PROGRAM_ID)) {
                return error.ConstraintOwner;
            }
            if (config.address) |addr| {
                if (!info.id.equals(addr)) {
                    return error.ConstraintAddress;
                }
            }
            if (config.mut and info.is_writable == 0) {
                return error.ConstraintMut;
            }
            if (config.signer and info.is_signer == 0) {
                return error.ConstraintSigner;
            }

            const data = stake_state.StakeStateV2.unpack(info.data[0..info.data_len]) catch {
                return error.AccountDidNotDeserialize;
            };

            return Self{ .info = info, .data = data };
        }

        /// Return the account public key.
        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        /// Return the underlying AccountInfo.
        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Convenience wrapper for immutable stake accounts.
pub const StakeAccountConst = StakeAccount(.{});

/// Convenience wrapper for mutable stake accounts.
pub const StakeAccountMut = StakeAccount(.{ .mut = true });

// ============================================================================
// Stake CPI helpers
// ============================================================================

/// Invoke Stake::Initialize.
pub fn initialize(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    rent_sysvar: *const AccountInfo,
    authorized: stake_instruction.Authorized,
    lockup: stake_instruction.Lockup,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.initialize(stake_account.id.*, authorized, lockup);
    var metas = built.accounts;
    const params = buildParams(2, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ stake_account.*, rent_sysvar.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::Authorize.
pub fn authorize(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    authority: *const AccountInfo,
    new_authority: *const AccountInfo,
    stake_authorize: stake_instruction.StakeAuthorize,
    custodian: ?*const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const custodian_key = if (custodian) |c| c.id.* else null;
    const built = stake_instruction.authorize(
        stake_account.id.*,
        authority.id.*,
        new_authority.id.*,
        stake_authorize,
        custodian_key,
    );
    var metas = built.accounts;
    const params = buildParams(4, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..built.num_accounts],
        .data = built.data[0..],
    });
    var infos: [4]AccountInfo = undefined;
    infos[0] = stake_account.*;
    infos[1] = clock_sysvar.*;
    infos[2] = authority.*;
    if (custodian) |c| {
        infos[3] = c.*;
    }
    try invokeInstruction(&ix, infos[0..built.num_accounts], signer_seeds);
}

/// Invoke Stake::DelegateStake.
pub fn delegateStake(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    vote_account: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    stake_history_sysvar: *const AccountInfo,
    stake_config: *const AccountInfo,
    authority: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.delegateStake(
        stake_account.id.*,
        vote_account.id.*,
        authority.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(6, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{
        stake_account.*,
        vote_account.*,
        clock_sysvar.*,
        stake_history_sysvar.*,
        stake_config.*,
        authority.*,
    };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::Split.
pub fn split(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    split_stake_account: *const AccountInfo,
    authority: *const AccountInfo,
    lamports: u64,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.split(
        stake_account.id.*,
        split_stake_account.id.*,
        authority.id.*,
        lamports,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ stake_account.*, split_stake_account.*, authority.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::Withdraw.
pub fn withdraw(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    recipient: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    stake_history_sysvar: *const AccountInfo,
    authority: *const AccountInfo,
    lamports: u64,
    custodian: ?*const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const custodian_key = if (custodian) |c| c.id.* else null;
    const built = stake_instruction.withdraw(
        stake_account.id.*,
        recipient.id.*,
        authority.id.*,
        lamports,
        custodian_key,
    );
    var metas = built.accounts;
    const params = buildParams(6, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..built.num_accounts],
        .data = built.data[0..],
    });
    var infos: [6]AccountInfo = undefined;
    infos[0] = stake_account.*;
    infos[1] = recipient.*;
    infos[2] = clock_sysvar.*;
    infos[3] = stake_history_sysvar.*;
    infos[4] = authority.*;
    if (custodian) |c| {
        infos[5] = c.*;
    }
    try invokeInstruction(&ix, infos[0..built.num_accounts], signer_seeds);
}

/// Invoke Stake::Deactivate.
pub fn deactivate(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    authority: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.deactivate(
        stake_account.id.*,
        authority.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ stake_account.*, clock_sysvar.*, authority.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::SetLockup.
pub fn setLockup(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    authority: *const AccountInfo,
    lockup_args: stake_instruction.LockupArgs,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.setLockup(
        stake_account.id.*,
        authority.id.*,
        lockup_args,
    );
    var metas = built.accounts;
    const params = buildParams(2, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..built.data_len],
    });
    const infos = [_]AccountInfo{ stake_account.*, authority.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::Merge.
pub fn merge(
    stake_program: *const AccountInfo,
    destination_stake: *const AccountInfo,
    source_stake: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    stake_history_sysvar: *const AccountInfo,
    authority: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.merge(
        destination_stake.id.*,
        source_stake.id.*,
        authority.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(5, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{
        destination_stake.*,
        source_stake.*,
        clock_sysvar.*,
        stake_history_sysvar.*,
        authority.*,
    };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::InitializeChecked.
pub fn initializeChecked(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    rent_sysvar: *const AccountInfo,
    staker: *const AccountInfo,
    withdrawer: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.initializeChecked(
        stake_account.id.*,
        staker.id.*,
        withdrawer.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(4, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{
        stake_account.*,
        rent_sysvar.*,
        staker.*,
        withdrawer.*,
    };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::AuthorizeChecked.
pub fn authorizeChecked(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    clock_sysvar: *const AccountInfo,
    authority: *const AccountInfo,
    new_authority: *const AccountInfo,
    stake_authorize: stake_instruction.StakeAuthorize,
    custodian: ?*const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const custodian_key = if (custodian) |c| c.id.* else null;
    const built = stake_instruction.authorizeChecked(
        stake_account.id.*,
        authority.id.*,
        new_authority.id.*,
        stake_authorize,
        custodian_key,
    );
    var metas = built.accounts;
    const params = buildParams(5, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..built.num_accounts],
        .data = built.data[0..],
    });
    var infos: [5]AccountInfo = undefined;
    infos[0] = stake_account.*;
    infos[1] = clock_sysvar.*;
    infos[2] = authority.*;
    infos[3] = new_authority.*;
    if (custodian) |c| {
        infos[4] = c.*;
    }
    try invokeInstruction(&ix, infos[0..built.num_accounts], signer_seeds);
}

/// Invoke Stake::SetLockupChecked.
pub fn setLockupChecked(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    authority: *const AccountInfo,
    lockup_args: stake_instruction.LockupCheckedArgs,
    new_custodian: ?*const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const custodian_key = if (new_custodian) |c| c.id.* else null;
    const built = stake_instruction.setLockupChecked(
        stake_account.id.*,
        authority.id.*,
        lockup_args,
        custodian_key,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..built.num_accounts],
        .data = built.data[0..built.data_len],
    });
    var infos: [3]AccountInfo = undefined;
    infos[0] = stake_account.*;
    infos[1] = authority.*;
    if (new_custodian) |c| {
        infos[2] = c.*;
    }
    try invokeInstruction(&ix, infos[0..built.num_accounts], signer_seeds);
}

/// Invoke Stake::GetMinimumDelegation.
pub fn getMinimumDelegation(
    stake_program: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.getMinimumDelegation();
    const params: [0]AccountParam = .{};
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos: [0]AccountInfo = .{};
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::DeactivateDelinquent.
pub fn deactivateDelinquent(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    delinquent_vote_account: *const AccountInfo,
    reference_vote_account: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.deactivateDelinquent(
        stake_account.id.*,
        delinquent_vote_account.id.*,
        reference_vote_account.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{
        stake_account.*,
        delinquent_vote_account.*,
        reference_vote_account.*,
    };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::Redelegate (deprecated).
pub fn redelegate(
    stake_program: *const AccountInfo,
    stake_account: *const AccountInfo,
    uninitialized_stake_account: *const AccountInfo,
    vote_account: *const AccountInfo,
    stake_config: *const AccountInfo,
    authority: *const AccountInfo,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.redelegate(
        stake_account.id.*,
        uninitialized_stake_account.id.*,
        vote_account.id.*,
        authority.id.*,
    );
    var metas = built.accounts;
    const params = buildParams(5, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{
        stake_account.*,
        uninitialized_stake_account.*,
        vote_account.*,
        stake_config.*,
        authority.*,
    };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::MoveStake.
pub fn moveStake(
    stake_program: *const AccountInfo,
    source_stake: *const AccountInfo,
    destination_stake: *const AccountInfo,
    authority: *const AccountInfo,
    lamports: u64,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.moveStake(
        source_stake.id.*,
        destination_stake.id.*,
        authority.id.*,
        lamports,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source_stake.*, destination_stake.*, authority.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

/// Invoke Stake::MoveLamports.
pub fn moveLamports(
    stake_program: *const AccountInfo,
    source_stake: *const AccountInfo,
    destination_stake: *const AccountInfo,
    authority: *const AccountInfo,
    lamports: u64,
    signer_seeds: ?[]const []const []const u8,
) StakeCpiError!void {
    const built = stake_instruction.moveLamports(
        source_stake.id.*,
        destination_stake.id.*,
        authority.id.*,
        lamports,
    );
    var metas = built.accounts;
    const params = buildParams(3, &metas);
    const ix = Instruction.from(.{
        .program_id = stake_program.id,
        .accounts = params[0..],
        .data = built.data[0..],
    });
    const infos = [_]AccountInfo{ source_stake.*, destination_stake.*, authority.* };
    try invokeInstruction(&ix, infos[0..], signer_seeds);
}

test "StakeAccount load parses state" {
    var stake_id = PublicKey.default();
    var owner = STAKE_PROGRAM_ID;
    var lamports: u64 = 1;
    var data: [stake_state.StakeStateV2.SIZE]u8 = undefined;
    @memset(&data, 0);

    const info = AccountInfo{
        .id = &stake_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = data.len,
        .data = data[0..].ptr,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    const Wrapper = StakeAccount(.{});
    _ = try Wrapper.load(&info);
}
