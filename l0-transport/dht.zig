//! RFC-0122: Kademlia-lite DHT for Capsule Discovery
//! Implements wide-area peer discovery using XOR distance metric.

const std = @import("std");
const net = std.net;

pub const K = 20; // Bucket size
pub const ID_LEN = 32; // 256-bit IDs (truncated Blake3)

pub const NodeId = [ID_LEN]u8;

/// XOR distance metric
pub fn distance(a: NodeId, b: NodeId) NodeId {
    var result: NodeId = undefined;
    for (0..ID_LEN) |i| {
        result[i] = a[i] ^ b[i];
    }
    return result;
}

/// Returns the index of the first set bit (distance order)
pub fn commonPrefixLen(id1: NodeId, id2: NodeId) usize {
    var count: usize = 0;
    for (0..ID_LEN) |i| {
        const x = id1[i] ^ id2[i];
        if (x == 0) {
            count += 8;
        } else {
            count += @clz(x);
            break;
        }
    }
    return count;
}

pub const RemoteNode = struct {
    id: NodeId,
    address: net.Address,
    last_seen: i64,
    key: [32]u8 = [_]u8{0} ** 32, // X25519 Public Key
};

pub const KBucket = struct {
    nodes: std.ArrayList(RemoteNode) = .{},

    pub fn deinit(self: *KBucket, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
    }
};

pub const RoutingTable = struct {
    self_id: NodeId,
    buckets: [ID_LEN * 8]KBucket,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, self_id: NodeId) RoutingTable {
        return RoutingTable{
            .self_id = self_id,
            .buckets = [_]KBucket{.{}} ** (ID_LEN * 8),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RoutingTable) void {
        for (0..self.buckets.len) |i| {
            self.buckets[i].deinit(self.allocator);
        }
    }

    pub fn update(self: *RoutingTable, node: RemoteNode) !void {
        const cpl = commonPrefixLen(self.self_id, node.id);
        const bucket_idx = if (cpl == ID_LEN * 8) ID_LEN * 8 - 1 else cpl;
        var bucket = &self.buckets[bucket_idx];

        // 1. If node exists, move to end (most recent)
        for (bucket.nodes.items, 0..) |existing, i| {
            if (std.mem.eql(u8, &existing.id, &node.id)) {
                _ = bucket.nodes.orderedRemove(i);
                try bucket.nodes.append(self.allocator, node);
                return;
            }
        }

        // 2. If bucket not full, add to end
        if (bucket.nodes.items.len < K) {
            try bucket.nodes.append(self.allocator, node);
        } else {
            // 3. Bucket full, ping oldest (front)
            // For now, we just don't add. TODO: Implement ping-and-replace
        }
    }

    pub fn findClosest(self: *RoutingTable, target: NodeId, count: usize) ![]RemoteNode {
        var results = std.ArrayList(RemoteNode){};
        defer results.deinit(self.allocator);

        // Collect all nodes from all buckets
        for (self.buckets) |bucket| {
            for (bucket.nodes.items) |node| {
                try results.append(self.allocator, node);
            }
        }

        // Sort by distance to target
        const SortContext = struct {
            target: NodeId,
            pub fn lessThan(ctx: @This(), a: RemoteNode, b: RemoteNode) bool {
                const dist_a = distance(a.id, ctx.target);
                const dist_b = distance(b.id, ctx.target);
                for (0..ID_LEN) |i| {
                    if (dist_a[i] < dist_b[i]) return true;
                    if (dist_a[i] > dist_b[i]) return false;
                }
                return false;
            }
        };

        std.sort.block(RemoteNode, results.items, SortContext{ .target = target }, SortContext.lessThan);

        const actual_count = if (results.items.len < count) results.items.len else count;
        const out = try self.allocator.alloc(RemoteNode, actual_count);
        @memcpy(out, results.items[0..actual_count]);
        return out;
    }

    pub fn getNodeCount(self: *const RoutingTable) usize {
        var count: usize = 0;
        for (self.buckets) |bucket| {
            count += bucket.nodes.items.len;
        }
        return count;
    }
};

pub const DhtService = struct {
    allocator: std.mem.Allocator,
    routing_table: RoutingTable,

    pub fn init(allocator: std.mem.Allocator, self_id: NodeId) DhtService {
        return .{
            .allocator = allocator,
            .routing_table = RoutingTable.init(allocator, self_id),
        };
    }

    pub fn deinit(self: *DhtService) void {
        self.routing_table.deinit();
    }

    pub fn getKnownNodeCount(self: *const DhtService) usize {
        return self.routing_table.getNodeCount();
    }
};
