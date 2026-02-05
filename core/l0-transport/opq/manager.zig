//! RFC-0020: OPQ (Offline Packet Queue) - Manager
//!
//! Orchestrates the flow of frames into the store, enforcing quotas and TTLs.

const std = @import("std");
const store = @import("./store.zig");
const quota = @import("./quota.zig");
const manifest = @import("./manifest.zig");
const sequencer = @import("./sequencer.zig");
const trust_resolver = @import("./trust_resolver.zig");
const lwf = @import("../lwf.zig");

pub const OPQManager = struct {
    allocator: std.mem.Allocator,
    policy: quota.Policy,
    store: store.WALStore,
    index: std.ArrayListUnmanaged(manifest.PacketSummary),
    trust_resolver: trust_resolver.TrustResolver,

    pub fn init(allocator: std.mem.Allocator, base_dir: []const u8, persona: quota.Persona, resolver: trust_resolver.TrustResolver) !OPQManager {
        const policy = quota.Policy.init(persona);
        const wal = try store.WALStore.init(allocator, base_dir, policy.segment_size);

        return OPQManager{
            .allocator = allocator,
            .policy = policy,
            .store = wal,
            .index = .{},
            .trust_resolver = resolver,
        };
    }

    pub fn deinit(self: *OPQManager) void {
        self.store.deinit();
        self.index.deinit(self.allocator);
    }

    /// Ingest a frame into the queue
    pub fn ingestFrame(self: *OPQManager, frame: *const lwf.LWFFrame) !void {
        // 1. Resolve Trust Category
        const category = self.trust_resolver.resolve(frame.header.source_hint);

        // 2. Resource Triage (Mechanism: Drop low-trust if busy)
        // In a real implementation, we'd check current_total_size vs policy.
        // For now, we allow the ingestion and rely on maintenance to prune.

        // 3. Append to WAL
        const loc = try self.store.appendFrame(frame);

        // 2. Update In-Memory Index (Summary)
        // Note: In real scenarios, queue_id should be deterministic or from header.
        // For now, we use a random ID or part of checksum.
        var q_id: [16]u8 = undefined;
        std.crypto.random.bytes(&q_id);

        try self.index.append(self.allocator, .{
            .queue_id = q_id,
            .sender_hint = frame.header.source_hint,
            .size = @intCast(loc.len),
            .priority = if (frame.header.flags & lwf.LWFFlags.PRIORITY != 0) .high else .normal,
            .created_at = std.time.timestamp(),
            .timestamp = frame.header.timestamp,
            .sequence = frame.header.sequence,
            .expires_at = std.time.timestamp() + self.policy.max_retention_seconds,
            .entropy_cost = frame.header.entropy_difficulty,
            .category = category,
        });

        // 5. Periodic maintenance
        try self.maintenance();
    }

    pub fn generateManifest(self: *OPQManager, recipient: [24]u8) !manifest.QueueManifest {
        var qm = manifest.QueueManifest.init(self.allocator, recipient);
        errdefer qm.deinit();

        for (self.index.items) |item| {
            // In a real relay, we would filter by recipient!
            // For now, we just add everything to the manifest.
            try qm.items.append(self.allocator, item);
            qm.total_count += 1;
            qm.total_size += item.size;
        }

        sequencer.sortDeterministically(qm.items.items);

        try qm.calculateMerkleRoot();
        return qm;
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
    var manager = try OPQManager.init(allocator, test_dir, .client, trust_resolver.TrustResolver.noop());
    defer manager.deinit();

    try std.testing.expectEqual(manager.policy.max_storage_bytes, 5 * 1024 * 1024);

    // 2. Ingest Sample Frame
    var frame = try lwf.LWFFrame.init(allocator, 10);
    defer frame.deinit(allocator);
    try manager.ingestFrame(&frame);

    // 3. Generate Manifest
    const recipient = [_]u8{0} ** 24;
    var mf = try manager.generateManifest(recipient);
    defer mf.deinit();

    try std.testing.expectEqual(mf.total_count, 1);
    try std.testing.expect(mf.total_size > 0);
    try std.testing.expect(!std.mem.eql(u8, &mf.merkle_root, &[_]u8{0} ** 32));
}

test "OPQ Manager: Deterministic Manifest Ordering" {
    const allocator = std.testing.allocator;
    const test_dir = "test_opq_ordering";

    std.fs.cwd().deleteTree(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    var manager = try OPQManager.init(allocator, test_dir, .relay, trust_resolver.TrustResolver.noop());
    defer manager.deinit();

    // 1. Ingest frames out of order
    // Frame A: Time 200, Seq 2
    var f1 = try lwf.LWFFrame.init(allocator, 10);
    defer f1.deinit(allocator);
    f1.header.timestamp = 200;
    f1.header.sequence = 2;
    f1.updateChecksum();
    try manager.ingestFrame(&f1);

    // Frame B: Time 100, Seq 1 (Should come first)
    var f2 = try lwf.LWFFrame.init(allocator, 10);
    defer f2.deinit(allocator);
    f2.header.timestamp = 100;
    f2.header.sequence = 1;
    f2.updateChecksum();
    try manager.ingestFrame(&f2);

    // 2. Generate Manifest
    const recipient = [_]u8{0} ** 24;
    var mf = try manager.generateManifest(recipient);
    defer mf.deinit();

    // 3. Verify Order: item[0] should be timestamp 100
    try std.testing.expectEqual(mf.items.items[0].timestamp, 100);
    try std.testing.expectEqual(mf.items.items[1].timestamp, 200);
}
