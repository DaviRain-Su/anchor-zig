//! Zig implementation of Anchor SystemAccount wrapper
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/accounts/system_account.rs

const sol = @import("solana_program_sdk");

const AccountInfo = sol.account.Account.Info;
const PublicKey = sol.PublicKey;

/// System account configuration.
pub const SystemAccountConfig = struct {
    address: ?PublicKey = null,
    mut: bool = false,
    signer: bool = false,
};

/// System-owned account wrapper.
///
/// Validates the account is owned by the system program.
pub fn SystemAccount(comptime config: SystemAccountConfig) type {
    return struct {
        const Self = @This();

        info: *const AccountInfo,

        pub const HAS_MUT: bool = config.mut;
        pub const HAS_SIGNER: bool = config.signer;

        pub fn load(info: *const AccountInfo) !Self {
            if (!info.owner_id.equals(sol.system_program.id)) {
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
            return Self{ .info = info };
        }

        pub fn key(self: Self) *const PublicKey {
            return self.info.id;
        }

        pub fn toAccountInfo(self: Self) *const AccountInfo {
            return self.info;
        }
    };
}

/// Convenience wrapper for immutable system accounts.
pub const SystemAccountConst = SystemAccount(.{});

/// Convenience wrapper for mutable system accounts.
pub const SystemAccountMut = SystemAccount(.{ .mut = true });

test "SystemAccount load validates owner" {
    var account_id = PublicKey.default();
    var owner = sol.system_program.id;
    var lamports: u64 = 1;
    var data: [0]u8 = undefined;

    const info = AccountInfo{
        .id = &account_id,
        .owner_id = &owner,
        .lamports = &lamports,
        .data_len = 0,
        .data = &data,
        .is_signer = 0,
        .is_writable = 0,
        .is_executable = 0,
    };

    _ = try SystemAccountConst.load(&info);
}
