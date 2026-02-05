//! RFC-0120: Reorder Buffer for Deterministic L1 Ingestion
//!
//! Hand-crafted for maximum efficiency. Ensures that frames are yielded
//! to the L1 state machine in a contiguous, monotonic sequence per sender.
//! This prevents out-of-order execution which is the primary source of
//! race conditions in distributed state machines.

const std = @import("std");
const manifest = @import("manifest.zig");

pub const ReorderBuffer = struct {
    allocator: std.mem.Allocator,
    next_expected_seq: std.AutoHashMapUnmanaged([24]u8, u32),
    pending_frames: std.AutoHashMapUnmanaged([24]u8, std.ArrayListUnmanaged(manifest.PacketSummary)),

    pub fn init(allocator: std.mem.Allocator) ReorderBuffer {
        return .{
            .allocator = allocator,
            .next_expected_seq = .{},
            .pending_frames = .{},
        };
    }

    pub fn deinit(self: *ReorderBuffer) void {
        self.next_expected_seq.deinit(self.allocator);
        var it = self.pending_frames.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.pending_frames.deinit(self.allocator);
    }

    /// Add a frame to the buffer.
    /// Returns a slice of frames that are now ready to be processed in order.
    /// The caller owns the returned slice.
    pub fn push(self: *ReorderBuffer, summary: manifest.PacketSummary) ![]manifest.PacketSummary {
        const sender = summary.sender_hint;
        const seq = summary.sequence;

        const entry = try self.next_expected_seq.getOrPut(self.allocator, sender);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        const next = entry.value_ptr.*;

        if (seq < next) {
            // Already processed or old, drop it
            return &[_]manifest.PacketSummary{};
        }

        if (seq == next) {
            // Perfect fit! Let's see if we can drain any pending ones too.
            var ready = std.ArrayList(manifest.PacketSummary).empty;
            errdefer ready.deinit(self.allocator);

            try ready.append(self.allocator, summary);
            entry.value_ptr.* += 1;

            // Check if we have the next ones in the pending list
            if (self.pending_frames.getPtr(sender)) |pending| {
                while (true) {
                    var found = false;
                    var i: usize = 0;
                    while (i < pending.items.len) {
                        if (pending.items[i].sequence == entry.value_ptr.*) {
                            try ready.append(self.allocator, pending.swapRemove(i));
                            entry.value_ptr.* += 1;
                            found = true;
                            // Reset search since we modified the list
                            break;
                        }
                        i += 1;
                    }
                    if (!found) break;
                }
            }

            return ready.toOwnedSlice(self.allocator);
        }

        // Ahead of sequence, buffer it
        const pending_entry = try self.pending_frames.getOrPut(self.allocator, sender);
        if (!pending_entry.found_existing) pending_entry.value_ptr.* = .{};
        try pending_entry.value_ptr.append(self.allocator, summary);

        return &[_]manifest.PacketSummary{};
    }

    /// Force yield everything for a sender (e.g. on timeout or disconnect)
    pub fn forceFlush(self: *ReorderBuffer, sender: [24]u8) ![]manifest.PacketSummary {
        if (self.pending_frames.getPtr(sender)) |pending| {
            // Sort them first to ensure deterministic yield even in flush
            const items = pending.items;
            std.sort.pdq(manifest.PacketSummary, items, {}, compareBySeq);

            const result = try self.allocator.dupe(manifest.PacketSummary, items);
            pending.clearRetainingCapacity();

            // Update next expected to avoid replaying these
            if (result.len > 0) {
                if (self.next_expected_seq.getPtr(sender)) |next| {
                    next.* = result[result.len - 1].sequence + 1;
                }
            }

            return result;
        }
        return &[_]manifest.PacketSummary{};
    }
};

fn compareBySeq(_: void, a: manifest.PacketSummary, b: manifest.PacketSummary) bool {
    return a.sequence < b.sequence;
}

test "ReorderBuffer: contiguous flow" {
    const allocator = std.testing.allocator;
    var rb = ReorderBuffer.init(allocator);
    defer rb.deinit();

    const sender = [_]u8{0xC} ** 24;

    // Push 0 -> Ready [0]
    const r1 = try rb.push(.{ .queue_id = [_]u8{0} ** 16, .sender_hint = sender, .size = 0, .priority = .normal, .created_at = 0, .timestamp = 0, .sequence = 0, .expires_at = 0, .entropy_cost = 0, .category = .peer });
    defer allocator.free(r1);
    try std.testing.expectEqual(r1.len, 1);
    try std.testing.expectEqual(r1[0].sequence, 0);

    // Push 2 -> Buffered
    const r2 = try rb.push(.{ .queue_id = [_]u8{0} ** 16, .sender_hint = sender, .size = 0, .priority = .normal, .created_at = 0, .timestamp = 0, .sequence = 2, .expires_at = 0, .entropy_cost = 0, .category = .peer });
    defer allocator.free(r2);
    try std.testing.expectEqual(r2.len, 0);

    // Push 1 -> Ready [1, 2]
    const r3 = try rb.push(.{ .queue_id = [_]u8{0} ** 16, .sender_hint = sender, .size = 0, .priority = .normal, .created_at = 0, .timestamp = 0, .sequence = 1, .expires_at = 0, .entropy_cost = 0, .category = .peer });
    defer allocator.free(r3);
    try std.testing.expectEqual(r3.len, 2);
    try std.testing.expectEqual(r3[0].sequence, 1);
    try std.testing.expectEqual(r3[1].sequence, 2);
}
