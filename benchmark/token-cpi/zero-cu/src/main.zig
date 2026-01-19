//! Minimal Token CPI
//!
//! Stripped down version to minimize overhead before CPI call.
//! The ~5000 CU CPI overhead is unavoidable (Solana runtime).

const std = @import("std");
const anchor = @import("sol_anchor_zig");
const spl = anchor.spl;
const sol = anchor.sdk;

const PublicKey = sol.public_key.PublicKey;
const Account = sol.account.Account;
const Context = sol.context.Context;
const AccountInfo = Account.Info;
const Instruction = sol.instruction.Instruction;
const AccountParam = Account.Param;

const TOKEN_PROGRAM_ID = spl.token.TOKEN_PROGRAM_ID;

// Anchor discriminator for "transfer"
const TRANSFER_DISC: u64 = @bitCast(anchor.discriminator.instructionDiscriminator("transfer"));

export fn entrypoint(input: [*]u8) u64 {
    // Minimal parsing - just load context
    const ctx = Context.load(input) catch return 1;
    
    // Check discriminator
    if (ctx.data.len < 16) return 1;
    const disc: *align(1) const u64 = @ptrCast(ctx.data.ptr);
    if (disc.* != TRANSFER_DISC) return 1;
    
    // Parse amount
    const amount = std.mem.readInt(u64, ctx.data[8..16], .little);
    
    // Get accounts (need at least 3: source, dest, authority)
    if (ctx.num_accounts < 3) return 1;
    const source = ctx.accounts[0];
    const dest = ctx.accounts[1];
    const auth = ctx.accounts[2];
    
    // Direct CPI - minimal overhead
    const account_params = [_]AccountParam{
        .{ .id = &source.ptr.id, .is_writable = true, .is_signer = false },
        .{ .id = &dest.ptr.id, .is_writable = true, .is_signer = false },
        .{ .id = &auth.ptr.id, .is_writable = false, .is_signer = true },
    };

    var data: [9]u8 = undefined;
    data[0] = 3; // SPL Token Transfer instruction
    std.mem.writeInt(u64, data[1..9], amount, .little);

    const ix = Instruction.from(.{
        .program_id = &TOKEN_PROGRAM_ID,
        .accounts = &account_params,
        .data = &data,
    });

    const account_infos = [_]AccountInfo{
        source.info(),
        dest.info(),
        auth.info(),
    };

    if (ix.invoke(&account_infos)) |_| {
        return 1;
    }

    return 0;
}
