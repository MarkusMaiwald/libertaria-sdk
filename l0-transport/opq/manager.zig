//! RFC-0020: OPQ (Offline Packet Queue) - Manager
//!
//! Orchestrates the flow of frames into the store, enforcing quotas and TTLs.

const std = @import("std");
const store = @import("store.zig");
const quota = @import("quota.zig");
const lwf = @import("lwf");

pub const OPQManager = struct {
    allocator: std.mem.Allocator,
    policy: quota.Policy,
    store: store.WALStore,

    pub fn init(allocator: std.mem.Allocator, base_dir: []const u8, persona: quota.Persona) !OPQManager {
        const policy = quota.Policy.init(persona);
        const wal = try store.WALStore.init(allocator, base_dir, policy.segment_size);

        return OPQManager{
            .allocator = allocator,
            .policy = policy,
            .store = wal,
        };
    }

    pub fn deinit(self: *OPQManager) void {
        self.store.deinit();
    }

    /// Ingest a frame into the queue
    pub fn ingestFrame(self: *OPQManager, frame: *const lwf.LWFFrame) !void {
        // 1. Append to WAL
        try self.store.appendFrame(frame);

        // 2. Periodic maintenance (could be on a timer, but here we do it after ingest)
        try self.maintenance();
    }

    pub fn maintenance(self: *OPQManager) !void {
        // 1. Prune by TTL
        _ = try self.store.prune(self.policy.max_retention_seconds);

        // 2. Prune by Size Quota
        _ = try self.store.pruneToSize(self.policy.max_storage_bytes);
    }
};

test "OPQ Manager: Policy Enforcement" {
    const allocator = std.testing.allocator;
    const test_dir = "test_opq_manager";

    std.fs.cwd().deleteTree(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    // 1. Client Policy: 5MB limit, 1hr TTL
    var manager = try OPQManager.init(allocator, test_dir, .client);
    defer manager.deinit();

    try std.testing.expectEqual(manager.policy.max_storage_bytes, 5 * 1024 * 1024);

    // 2. Ingest Sample Frame
    var frame = try lwf.LWFFrame.init(allocator, 10);
    defer frame.deinit(allocator);
    try manager.ingestFrame(&frame);
}
