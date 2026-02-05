//! RFC-0020: OPQ Manifests & Summaries
//!
//! Provides bandwidth-efficient triage of queued packets.

const std = @import("std");
const merkle = @import("./merkle.zig");
const quota = @import("./quota.zig");

pub const Priority = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,
    critical = 3,
};

pub const PacketSummary = struct {
    queue_id: [16]u8,
    sender_hint: [24]u8, // DID hint
    size: u32,
    priority: Priority,
    created_at: i64, // WALL time (for expiry)
    timestamp: u64, // L0 nanoseconds (for ordering)
    sequence: u32, // L0 sequence (for ordering/replay)
    expires_at: i64,
    entropy_cost: u16,
    category: quota.TrustCategory,
};

pub const QueueManifest = struct {
    allocator: std.mem.Allocator,
    recipient_hint: [24]u8,
    total_count: usize,
    total_size: u64,
    items: std.ArrayListUnmanaged(PacketSummary),
    merkle_root: [32]u8,

    pub fn init(allocator: std.mem.Allocator, recipient: [24]u8) QueueManifest {
        return .{
            .allocator = allocator,
            .recipient_hint = recipient,
            .total_count = 0,
            .total_size = 0,
            .items = .{},
            .merkle_root = [_]u8{0} ** 32,
        };
    }

    pub fn deinit(self: *QueueManifest) void {
        self.items.deinit(self.allocator);
    }

    pub fn calculateMerkleRoot(self: *QueueManifest) !void {
        var tree = merkle.MerkleTree.init(self.allocator);
        defer tree.deinit();

        for (self.items.items) |item| {
            // Hash the summary to form a leaf
            var hasher = std.crypto.hash.Blake3.init(.{});
            hasher.update(&item.queue_id);
            hasher.update(&item.sender_hint);
            hasher.update(std.mem.asBytes(&item.size));
            hasher.update(std.mem.asBytes(&item.created_at));
            var leaf: [32]u8 = undefined;
            hasher.final(&leaf);
            try tree.insert(leaf);
        }

        self.merkle_root = tree.getRoot();
    }
};
