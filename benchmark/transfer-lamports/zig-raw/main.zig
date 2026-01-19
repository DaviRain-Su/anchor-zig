//! Raw Zig Transfer Lamports - No framework overhead
//!
//! Transfers lamports from source account to destination account.
//! Amount is specified as u64 in instruction data.

const std = @import("std");
const sol = @import("solana_program_sdk");

fn processInstruction(
    _: *sol.PublicKey,
    accounts: []sol.Account,
    data: []const u8,
) sol.ProgramResult {
    const source = accounts[0];
    const destination = accounts[1];
    const amount = std.mem.bytesToValue(u64, data[0..8]);

    source.lamports().* -= amount;
    destination.lamports().* += amount;

    return .ok;
}

comptime {
    sol.entrypoint(&processInstruction);
}
