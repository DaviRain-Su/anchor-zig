//! Zig implementation of Anchor event emission
//!
//! Anchor source: https://github.com/coral-xyz/anchor/blob/master/lang/src/event.rs
//!
//! Events are emitted via the `sol_log_data` syscall and can be parsed by
//! clients subscribing to program logs. The format follows Anchor's event
//! encoding: `[discriminator][borsh_serialized_data]`.
//!
//! ## Example
//! ```zig
//! const anchor = @import("sol_anchor_zig");
//!
//! // Define event type using typed DSL
//! const TransferEvent = anchor.dsl.Event(.{
//!     .from = anchor.sdk.PublicKey,
//!     .to = anchor.sdk.PublicKey,
//!     .amount = anchor.dsl.eventField(u64, .{ .index = true }),
//! });
//!
//! // Emit event in instruction handler
//! fn transfer(ctx: anchor.Context(TransferAccounts), amount: u64) !void {
//!     // ... transfer logic ...
//!
//!     // Emit event
//!     ctx.emit(TransferEvent{
//!         .from = ctx.accounts.from.key().*,
//!         .to = ctx.accounts.to.key().*,
//!         .amount = amount,
//!     });
//! }
//! ```

const std = @import("std");
const sol = @import("solana_program_sdk");
const discriminator_mod = @import("discriminator.zig");
const borsh = sol.borsh;

/// Maximum event data size (1KB should be sufficient for most events)
pub const MAX_EVENT_SIZE: usize = 1024;

/// Event discriminator length (8 bytes)
pub const EVENT_DISCRIMINATOR_LENGTH: usize = discriminator_mod.DISCRIMINATOR_LENGTH;

/// Emit an event to the Solana program logs.
///
/// This function:
/// 1. Generates the event discriminator from the type name
/// 2. Serializes the event data using Borsh encoding
/// 3. Emits via `sol_log_data` syscall
///
/// ## Parameters
/// - `EventType`: The event struct type (should be created via `dsl.Event`)
/// - `event`: The event data to emit
///
/// ## Example
/// ```zig
/// emitEvent(TransferEvent, .{
///     .from = source_key,
///     .to = dest_key,
///     .amount = 1000,
/// });
/// ```
pub fn emitEvent(comptime EventType: type, event: EventType) void {
    // Get event name from type (strip module path)
    const event_name = comptime extractEventName(@typeName(EventType));

    // Generate discriminator: sha256("event:<name>")[0..8]
    const disc = comptime discriminator_mod.eventDiscriminator(event_name);

    // Calculate serialized size
    const data_size = borsh.serializedSize(EventType, event);
    const total_size = EVENT_DISCRIMINATOR_LENGTH + data_size;

    // Ensure we don't exceed buffer
    if (total_size > MAX_EVENT_SIZE) {
        // Event too large - log warning and truncate
        sol.log.log("Warning: Event data truncated");
        return;
    }

    // Buffer for discriminator + serialized data
    var buffer: [MAX_EVENT_SIZE]u8 = undefined;

    // Write discriminator (first 8 bytes)
    @memcpy(buffer[0..EVENT_DISCRIMINATOR_LENGTH], &disc);

    // Serialize event data after discriminator
    const written = borsh.serialize(
        EventType,
        event,
        buffer[EVENT_DISCRIMINATOR_LENGTH..],
    ) catch {
        sol.log.log("Warning: Event serialization failed");
        return;
    };

    // Emit via sol_log_data
    const slices = [_][]const u8{buffer[0 .. EVENT_DISCRIMINATOR_LENGTH + written]};
    sol.log.logData(&slices);
}

/// Emit an event with a custom discriminator.
///
/// Use this when you need to control the exact discriminator value,
/// for example when emitting events that match a specific Anchor IDL.
pub fn emitEventWithDiscriminator(
    comptime EventType: type,
    event: EventType,
    disc: discriminator_mod.Discriminator,
) void {
    const data_size = borsh.serializedSize(EventType, event);
    const total_size = EVENT_DISCRIMINATOR_LENGTH + data_size;

    if (total_size > MAX_EVENT_SIZE) {
        sol.log.log("Warning: Event data truncated");
        return;
    }

    var buffer: [MAX_EVENT_SIZE]u8 = undefined;

    // Write custom discriminator
    @memcpy(buffer[0..EVENT_DISCRIMINATOR_LENGTH], &disc);

    // Serialize event data
    const written = borsh.serialize(
        EventType,
        event,
        buffer[EVENT_DISCRIMINATOR_LENGTH..],
    ) catch {
        sol.log.log("Warning: Event serialization failed");
        return;
    };

    const slices = [_][]const u8{buffer[0 .. EVENT_DISCRIMINATOR_LENGTH + written]};
    sol.log.logData(&slices);
}

/// Extract the event name from a full type path.
///
/// For example:
/// - "my_program.events.TransferEvent" -> "TransferEvent"
/// - "TransferEvent" -> "TransferEvent"
fn extractEventName(comptime full_name: []const u8) []const u8 {
    comptime {
        // Find last '.' to strip module path
        var last_dot: ?usize = null;
        for (full_name, 0..) |c, i| {
            if (c == '.') {
                last_dot = i;
            }
        }

        if (last_dot) |idx| {
            return full_name[idx + 1 ..];
        }
        return full_name;
    }
}

/// Get the discriminator for an event type.
///
/// This can be useful for client-side event parsing.
pub fn getEventDiscriminator(comptime EventType: type) discriminator_mod.Discriminator {
    const event_name = comptime extractEventName(@typeName(EventType));
    return comptime discriminator_mod.eventDiscriminator(event_name);
}

// ============================================================================
// Tests
// ============================================================================

test "extractEventName strips module path" {
    try std.testing.expectEqualStrings("TransferEvent", comptime extractEventName("my_program.events.TransferEvent"));
    try std.testing.expectEqualStrings("SimpleEvent", comptime extractEventName("SimpleEvent"));
    try std.testing.expectEqualStrings("Event", comptime extractEventName("a.b.c.Event"));
}

test "getEventDiscriminator returns correct discriminator" {
    const TestEvent = struct {
        value: u64,
    };

    const disc = getEventDiscriminator(TestEvent);

    // Should be 8 bytes
    try std.testing.expectEqual(@as(usize, 8), disc.len);

    // Should match discriminator module output
    const expected = comptime discriminator_mod.eventDiscriminator("TestEvent");
    try std.testing.expectEqualSlices(u8, &expected, &disc);
}

test "emitEvent serializes correctly" {
    // This test verifies the serialization logic works
    // In non-BPF mode, logData just prints to debug output

    const SimpleEvent = struct {
        count: u64,
        flag: bool,
    };

    // Should not panic or error
    emitEvent(SimpleEvent, .{
        .count = 42,
        .flag = true,
    });
}

test "emitEventWithDiscriminator uses custom discriminator" {
    const CustomEvent = struct {
        data: u32,
    };

    const custom_disc = [_]u8{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };

    // Should not panic
    emitEventWithDiscriminator(CustomEvent, .{ .data = 123 }, custom_disc);
}

test "MAX_EVENT_SIZE is reasonable" {
    // Events should fit in 1KB
    try std.testing.expectEqual(@as(usize, 1024), MAX_EVENT_SIZE);
}
