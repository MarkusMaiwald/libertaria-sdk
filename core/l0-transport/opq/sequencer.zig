//! RFC-0020 & RFC-0120: Deterministic Frame Sequencer
//!
//! Ensures that frames are presented to L1 in a stable, deterministic order
//! regardless of network arrival order. This is critical for state machine
//! consistency and preventing race conditions in the Reality Tunnel.

const std = @import("std");
const manifest = @import("./manifest.zig");

/// Sorts a slice of PacketSummaries deterministically.
/// Ordering Doctrine:
/// 1. Primary: Source Hint (truncated DID) - groups frames by sender
/// 2. Secondary: Timestamp (L0 nanoseconds) - causal ordering
/// 3. Tertiary: Sequence (Tie-breaker for same-nanosecond frames)
/// 4. Quaternary: QueueID (Force stability for identical metadata)
pub fn sortDeterministically(items: []manifest.PacketSummary) void {
    std.sort.pdq(manifest.PacketSummary, items, {}, comparePackets);
}

fn comparePackets(_: void, a: manifest.PacketSummary, b: manifest.PacketSummary) bool {
    // 1. Source Hint
    const hint_cmp = std.mem.order(u8, &a.sender_hint, &b.sender_hint);
    if (hint_cmp != .eq) return hint_cmp == .lt;

    // 2. Timestamp
    if (a.timestamp != b.timestamp) return a.timestamp < b.timestamp;

    // 3. Sequence
    if (a.sequence != b.sequence) return a.sequence < b.sequence;

    // 4. Queue ID (Total Stability)
    return std.mem.order(u8, &a.queue_id, &b.queue_id) == .lt;
}

pub const ReplayFilter = struct {
    last_sequences: std.AutoHashMapUnmanaged([24]u8, u32),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ReplayFilter {
        return .{
            .last_sequences = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ReplayFilter) void {
        self.last_sequences.deinit(self.allocator);
    }

    /// Checks if a packet is a replay.
    /// Returns true if the packet should be processed (new sequence),
    /// false if it should be dropped (replay or old).
    pub fn isNew(self: *ReplayFilter, sender: [24]u8, sequence: u32) !bool {
        const entry = try self.last_sequences.getOrPut(self.allocator, sender);
        if (!entry.found_existing) {
            entry.value_ptr.* = sequence;
            return true;
        }

        if (sequence > entry.value_ptr.*) {
            entry.value_ptr.* = sequence;
            return true;
        }

        return false; // Replay or old packet
    }
};

test "Deterministic Sorting" {
    var summaries = [_]manifest.PacketSummary{
        .{
            .queue_id = [_]u8{3} ** 16,
            .sender_hint = [_]u8{0xA} ** 24,
            .size = 100,
            .priority = .normal,
            .created_at = 0,
            .timestamp = 200,
            .sequence = 2,
            .expires_at = 0,
            .entropy_cost = 0,
            .category = .peer,
        },
        .{
            .queue_id = [_]u8{1} ** 16,
            .sender_hint = [_]u8{0xA} ** 24,
            .size = 100,
            .priority = .normal,
            .created_at = 0,
            .timestamp = 100,
            .sequence = 1,
            .expires_at = 0,
            .entropy_cost = 0,
            .category = .peer,
        },
        .{
            .queue_id = [_]u8{2} ** 16,
            .sender_hint = [_]u8{0xB} ** 24,
            .size = 100,
            .priority = .normal,
            .created_at = 0,
            .timestamp = 50,
            .sequence = 5,
            .expires_at = 0,
            .entropy_cost = 0,
            .category = .peer,
        },
    };

    sortDeterministically(&summaries);

    // Source A comes before Source B
    // Within Source A, timestamp 100 comes before 200
    try std.testing.expectEqual(summaries[0].sender_hint[0], 0xA);
    try std.testing.expectEqual(summaries[0].timestamp, 100);
    try std.testing.expectEqual(summaries[1].timestamp, 200);
    try std.testing.expectEqual(summaries[2].sender_hint[0], 0xB);
}

test "Replay Filter" {
    const allocator = std.testing.allocator;
    var filter = ReplayFilter.init(allocator);
    defer filter.deinit();

    const sender = [_]u8{0xC} ** 24;

    try std.testing.expect(try filter.isNew(sender, 10));
    try std.testing.expect(try filter.isNew(sender, 11));
    try std.testing.expect(!(try filter.isNew(sender, 10))); // Replay
    try std.testing.expect(!(try filter.isNew(sender, 5))); // Older
}
