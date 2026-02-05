//! Quasar Vector Lattice (QVL) - Trust Graph Engine
//!
//! RFC-0120: Compact Trust Graph Implementation
//!
//! This module implements the foundational trust DAG for Libertaria.
//! Optimized for Kenya Rule compliance:
//! - u32 node indices instead of 64-byte DIDs
//! - 5-byte packed edge weights
//! - O(1) direct trust lookup
//! - O(depth) Proof-of-Path verification
//!
//! Memory budget: 100K nodes = 400KB (vs 6.4MB with raw DIDs)

const std = @import("std");
const soulkey = @import("soulkey");
const crypto = @import("crypto");

/// Trust visibility levels (privacy control)
/// Per RFC-0120 S4.3.1: Alice never broadcasts her full Trust DAG
pub const TrustVisibility = enum(u8) {
    /// Only I can see this edge (default)
    private = 0,
    /// The trustee can see I trust them
    bilateral = 1,
    /// Anyone in my trust graph can see this edge
    friends = 2,
    /// Public: helps routing but leaks metadata
    /// USE SPARINGLY - only for public figures/services
    public = 3,
};

/// Trust level controlling transitive depth
pub const TrustLevel = enum(u8) {
    /// Direct trust only (no transitivity)
    direct = 0,
    /// Trust their direct contacts
    one_hop = 1,
    /// Trust contacts of contacts
    two_hop = 2,
    /// Default maximum (RFC-0010 Membrane Agent)
    full = 3,
};

/// Compact edge weight: 5 bytes vs ~100+ bytes
/// Per RFC-0120 S4.3.2
pub const TrustEdge = packed struct {
    /// Target node index
    target_idx: u32,
    /// Trust level (controls transitive depth)
    level: TrustLevel,
    /// Unix timestamp expiration (fine until 2106)
    expires_at: u32,
    /// Visibility setting (privacy control)
    visibility: TrustVisibility,

    pub const SERIALIZED_SIZE = 10;

    pub fn isExpired(self: TrustEdge, current_time: u64) bool {
        if (self.expires_at == 0) return false; // No expiration
        return current_time > @as(u64, self.expires_at);
    }

    pub fn serialize(self: TrustEdge) [SERIALIZED_SIZE]u8 {
        var buf: [SERIALIZED_SIZE]u8 = undefined;
        std.mem.writeInt(u32, buf[0..4], self.target_idx, .little);
        buf[4] = @intFromEnum(self.level);
        std.mem.writeInt(u32, buf[5..9], self.expires_at, .little);
        buf[9] = @intFromEnum(self.visibility);
        return buf;
    }

    pub fn deserialize(data: *const [SERIALIZED_SIZE]u8) TrustEdge {
        return TrustEdge{
            .target_idx = std.mem.readInt(u32, data[0..4], .little),
            .level = @enumFromInt(data[4]),
            .expires_at = std.mem.readInt(u32, data[5..9], .little),
            .visibility = @enumFromInt(data[9]),
        };
    }
};

/// Edge list type (managed ArrayList)
const EdgeList = std.ArrayListUnmanaged(TrustEdge);

/// Compact trust graph optimized for mobile RAM
/// Per RFC-0120 S4.3.2
pub const CompactTrustGraph = struct {
    /// Map DID hash (first 4 bytes) → node index
    /// Collision handling: full DID stored in did_storage
    node_map: std.AutoHashMap(u32, u32),

    /// Adjacency list: each node has list of outgoing edges
    adjacency: std.ArrayListUnmanaged(EdgeList),

    /// DID storage for reverse lookup (32 bytes each)
    did_storage: std.ArrayListUnmanaged([32]u8),

    /// Root node index (my identity)
    root_idx: u32,

    /// Configuration
    config: Config,

    /// Allocator
    allocator: std.mem.Allocator,

    pub const Config = struct {
        /// Maximum trust depth allowed
        max_trust_depth: u8 = 3,
        /// Maximum nodes to store (Kenya constraint)
        max_nodes: u32 = 10_000,
        /// Maximum edges per node
        max_edges_per_node: u32 = 100,
    };

    pub const Error = error{
        NodeLimitExceeded,
        EdgeLimitExceeded,
        NodeNotFound,
        SelfTrustNotAllowed,
        DuplicateEdge,
        OutOfMemory,
    };

    /// Initialize a new trust graph with the given root DID
    pub fn init(allocator: std.mem.Allocator, root_did: [32]u8, config: Config) Error!CompactTrustGraph {
        var self = CompactTrustGraph{
            .node_map = std.AutoHashMap(u32, u32).init(allocator),
            .adjacency = .{},
            .did_storage = .{},
            .root_idx = 0,
            .config = config,
            .allocator = allocator,
        };

        // Insert root node
        _ = try self.getOrInsertNode(root_did);

        return self;
    }

    pub fn deinit(self: *CompactTrustGraph) void {
        for (self.adjacency.items) |*adj| {
            adj.deinit(self.allocator);
        }
        self.adjacency.deinit(self.allocator);
        self.did_storage.deinit(self.allocator);
        self.node_map.deinit();
    }

    /// Get or create node index for a DID
    pub fn getOrInsertNode(self: *CompactTrustGraph, did: [32]u8) Error!u32 {
        // Hash DID to u32 for map lookup
        const did_hash = hashDid(did);

        if (self.node_map.get(did_hash)) |idx| {
            // Verify it's the same DID (handle collisions)
            if (std.mem.eql(u8, &self.did_storage.items[idx], &did)) {
                return idx;
            }
            // Collision: linear probe (rare case)
            // For simplicity, just use sequential index
        }

        // Check limit
        if (self.did_storage.items.len >= self.config.max_nodes) {
            return Error.NodeLimitExceeded;
        }

        // Create new node
        const idx: u32 = @intCast(self.did_storage.items.len);

        self.did_storage.append(self.allocator, did) catch return Error.OutOfMemory;
        self.adjacency.append(self.allocator, .{}) catch return Error.OutOfMemory;
        self.node_map.put(did_hash, idx) catch return Error.OutOfMemory;

        return idx;
    }

    /// Get node index for a DID (returns null if not found)
    pub fn getNode(self: *const CompactTrustGraph, did: [32]u8) ?u32 {
        const did_hash = hashDid(did);
        if (self.node_map.get(did_hash)) |idx| {
            if (std.mem.eql(u8, &self.did_storage.items[idx], &did)) {
                return idx;
            }
        }
        return null;
    }

    /// Get DID for a node index
    pub fn getDid(self: *const CompactTrustGraph, idx: u32) ?[32]u8 {
        if (idx >= self.did_storage.items.len) return null;
        return self.did_storage.items[idx];
    }

    /// Check direct trust: O(E) where E is edges for truster
    /// In practice, E << 100. so effectively O(1)
    pub fn hasDirectTrust(self: *const CompactTrustGraph, truster_idx: u32, trustee_idx: u32) bool {
        if (truster_idx >= self.adjacency.items.len) return false;

        const edges = self.adjacency.items[truster_idx].items;
        for (edges) |edge| {
            if (edge.target_idx == trustee_idx) {
                return true;
            }
        }
        return false;
    }

    /// Check direct trust by DID
    pub fn hasDirectTrustByDid(self: *const CompactTrustGraph, truster: [32]u8, trustee: [32]u8) bool {
        const truster_idx = self.getNode(truster) orelse return false;
        const trustee_idx = self.getNode(trustee) orelse return false;
        return self.hasDirectTrust(truster_idx, trustee_idx);
    }

    /// Grant trust from root to target DID
    pub fn grantTrust(
        self: *CompactTrustGraph,
        target_did: [32]u8,
        level: TrustLevel,
        visibility: TrustVisibility,
        expires_at: u32,
    ) Error!void {
        const target_idx = try self.getOrInsertNode(target_did);

        if (target_idx == self.root_idx) {
            return Error.SelfTrustNotAllowed;
        }

        // Check if edge already exists
        var edges = &self.adjacency.items[self.root_idx];
        for (edges.items) |*edge| {
            if (edge.target_idx == target_idx) {
                // Update existing edge
                edge.level = level;
                edge.visibility = visibility;
                edge.expires_at = expires_at;
                return;
            }
        }

        // Check edge limit
        if (edges.items.len >= self.config.max_edges_per_node) {
            return Error.EdgeLimitExceeded;
        }

        // Add new edge
        edges.append(self.allocator, TrustEdge{
            .target_idx = target_idx,
            .level = level,
            .visibility = visibility,
            .expires_at = expires_at,
        }) catch return Error.OutOfMemory;
    }

    /// Revoke trust from root to target DID
    pub fn revokeTrust(self: *CompactTrustGraph, target_did: [32]u8) Error!void {
        const target_idx = self.getNode(target_did) orelse return Error.NodeNotFound;

        var edges = &self.adjacency.items[self.root_idx];
        var i: usize = 0;
        while (i < edges.items.len) {
            if (edges.items[i].target_idx == target_idx) {
                _ = edges.swapRemove(i);
                return;
            }
            i += 1;
        }
    }

    /// Get trust edge from root to target (if exists)
    pub fn getTrustEdge(self: *const CompactTrustGraph, target_did: [32]u8) ?TrustEdge {
        const target_idx = self.getNode(target_did) orelse return null;

        const edges = self.adjacency.items[self.root_idx].items;
        for (edges) |edge| {
            if (edge.target_idx == target_idx) {
                return edge;
            }
        }
        return null;
    }

    /// BFS path finding (sender-side only)
    /// Returns path as list of node indices, or null if no path exists
    pub fn findPath(
        self: *const CompactTrustGraph,
        from_did: [32]u8,
        to_did: [32]u8,
    ) ?[]u32 {
        const from_idx = self.getNode(from_did) orelse return null;
        const to_idx = self.getNode(to_did) orelse return null;

        if (from_idx == to_idx) {
            // Same node - return single element path
            var path = self.allocator.alloc(u32, 1) catch return null;
            path[0] = from_idx;
            return path;
        }

        // BFS with parent tracking
        var visited = std.AutoHashMap(u32, u32).init(self.allocator);
        defer visited.deinit();

        var queue: std.ArrayListUnmanaged(u32) = .{};
        defer queue.deinit(self.allocator);

        queue.append(self.allocator, from_idx) catch return null;
        visited.put(from_idx, from_idx) catch return null; // Mark start

        while (queue.items.len > 0) {
            const current = queue.orderedRemove(0);

            if (current >= self.adjacency.items.len) continue;

            for (self.adjacency.items[current].items) |edge| {
                if (visited.contains(edge.target_idx)) continue;

                visited.put(edge.target_idx, current) catch return null;

                if (edge.target_idx == to_idx) {
                    // Found! Reconstruct path
                    return self.reconstructPath(visited, from_idx, to_idx);
                }

                // Check depth limit
                const depth = self.pathDepth(visited, edge.target_idx, from_idx);
                if (depth < self.config.max_trust_depth) {
                    queue.append(self.allocator, edge.target_idx) catch return null;
                }
            }
        }

        return null; // No path found
    }

    fn reconstructPath(
        self: *const CompactTrustGraph,
        parents: std.AutoHashMap(u32, u32),
        from_idx: u32,
        to_idx: u32,
    ) ?[]u32 {
        // Count path length
        var length: usize = 1;
        var current = to_idx;
        while (current != from_idx) {
            current = parents.get(current) orelse return null;
            length += 1;
            if (length > self.config.max_trust_depth + 1) return null; // Safety
        }

        // Allocate and fill path
        var path = self.allocator.alloc(u32, length) catch return null;

        current = to_idx;
        var i: usize = length;
        while (i > 0) {
            i -= 1;
            path[i] = current;
            if (current == from_idx) break;
            current = parents.get(current) orelse {
                self.allocator.free(path);
                return null;
            };
        }

        return path;
    }

    fn pathDepth(
        self: *const CompactTrustGraph,
        parents: std.AutoHashMap(u32, u32),
        node: u32,
        start: u32,
    ) u8 {
        _ = self;
        var depth: u8 = 0;
        var current = node;
        while (current != start and depth < 255) {
            current = parents.get(current) orelse break;
            depth += 1;
        }
        return depth;
    }

    /// Count total nodes in graph
    pub fn nodeCount(self: *const CompactTrustGraph) usize {
        return self.did_storage.items.len;
    }

    /// Count total edges from root
    pub fn rootEdgeCount(self: *const CompactTrustGraph) usize {
        if (self.root_idx >= self.adjacency.items.len) return 0;
        return self.adjacency.items[self.root_idx].items.len;
    }

    /// Get all direct trustees (nodes I trust)
    pub fn getDirectTrustees(self: *const CompactTrustGraph) []const TrustEdge {
        if (self.root_idx >= self.adjacency.items.len) return &[_]TrustEdge{};
        return self.adjacency.items[self.root_idx].items;
    }

    /// Hash DID to u32 for map key
    fn hashDid(did: [32]u8) u32 {
        // Use first 4 bytes as hash (collision handled by full DID comparison)
        return std.mem.readInt(u32, did[0..4], .little);
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "CompactTrustGraph: init and basic operations" {
    const allocator = std.testing.allocator;

    var root_did: [32]u8 = undefined;
    @memset(&root_did, 0x01);

    var graph = try CompactTrustGraph.init(allocator, root_did, .{});
    defer graph.deinit();

    // Root should be node 0
    try std.testing.expectEqual(@as(u32, 0), graph.root_idx);
    try std.testing.expectEqual(@as(usize, 1), graph.nodeCount());
}

test "CompactTrustGraph: grant and revoke trust" {
    const allocator = std.testing.allocator;

    var root_did: [32]u8 = undefined;
    @memset(&root_did, 0x01);

    var target_did: [32]u8 = undefined;
    @memset(&target_did, 0x02);

    var graph = try CompactTrustGraph.init(allocator, root_did, .{});
    defer graph.deinit();

    // Grant trust
    try graph.grantTrust(target_did, .full, .bilateral, 0);

    try std.testing.expectEqual(@as(usize, 2), graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 1), graph.rootEdgeCount());
    try std.testing.expect(graph.hasDirectTrustByDid(root_did, target_did));

    // Revoke trust
    try graph.revokeTrust(target_did);

    try std.testing.expectEqual(@as(usize, 0), graph.rootEdgeCount());
    try std.testing.expect(!graph.hasDirectTrustByDid(root_did, target_did));
}

test "CompactTrustGraph: find path" {
    const allocator = std.testing.allocator;

    // Create chain: A -> B -> C
    var did_a: [32]u8 = undefined;
    @memset(&did_a, 0x0A);

    var did_b: [32]u8 = undefined;
    @memset(&did_b, 0x0B);

    var did_c: [32]u8 = undefined;
    @memset(&did_c, 0x0C);

    var graph = try CompactTrustGraph.init(allocator, did_a, .{});
    defer graph.deinit();

    // A trusts B
    try graph.grantTrust(did_b, .full, .bilateral, 0);

    // Manually add B -> C edge
    const b_idx = graph.getNode(did_b).?;
    const c_idx = try graph.getOrInsertNode(did_c);

    try graph.adjacency.items[b_idx].append(allocator, TrustEdge{
        .target_idx = c_idx,
        .level = .full,
        .visibility = .bilateral,
        .expires_at = 0,
    });

    // Find path A -> C
    const path = graph.findPath(did_a, did_c);
    try std.testing.expect(path != null);
    defer allocator.free(path.?);

    try std.testing.expectEqual(@as(usize, 3), path.?.len);
    try std.testing.expectEqual(@as(u32, 0), path.?[0]); // A
    try std.testing.expectEqual(@as(u32, 1), path.?[1]); // B
    try std.testing.expectEqual(@as(u32, 2), path.?[2]); // C
}

test "CompactTrustGraph: self trust not allowed" {
    const allocator = std.testing.allocator;

    var root_did: [32]u8 = undefined;
    @memset(&root_did, 0x01);

    var graph = try CompactTrustGraph.init(allocator, root_did, .{});
    defer graph.deinit();

    // Try to trust self
    const result = graph.grantTrust(root_did, .full, .bilateral, 0);
    try std.testing.expectError(CompactTrustGraph.Error.SelfTrustNotAllowed, result);
}

test "CompactTrustGraph: node limit respected" {
    const allocator = std.testing.allocator;

    var root_did: [32]u8 = undefined;
    @memset(&root_did, 0x01);

    var graph = try CompactTrustGraph.init(allocator, root_did, .{ .max_nodes = 3 });
    defer graph.deinit();

    var did2: [32]u8 = undefined;
    @memset(&did2, 0x02);
    try graph.grantTrust(did2, .full, .bilateral, 0);

    var did3: [32]u8 = undefined;
    @memset(&did3, 0x03);
    try graph.grantTrust(did3, .full, .bilateral, 0);

    // Should fail - at limit
    var did4: [32]u8 = undefined;
    @memset(&did4, 0x04);
    const result = graph.grantTrust(did4, .full, .bilateral, 0);
    try std.testing.expectError(CompactTrustGraph.Error.NodeLimitExceeded, result);
}

test "TrustEdge: serialization roundtrip" {
    const edge = TrustEdge{
        .target_idx = 12345,
        .level = .two_hop,
        .expires_at = 1706652000,
        .visibility = .friends,
    };

    const serialized = edge.serialize();
    const deserialized = TrustEdge.deserialize(&serialized);

    try std.testing.expectEqual(edge.target_idx, deserialized.target_idx);
    try std.testing.expectEqual(edge.level, deserialized.level);
    try std.testing.expectEqual(edge.expires_at, deserialized.expires_at);
    try std.testing.expectEqual(edge.visibility, deserialized.visibility);
}

test "TrustEdge: expiration check" {
    const edge = TrustEdge{
        .target_idx = 1,
        .level = .full,
        .expires_at = 1706652000, // Some timestamp
        .visibility = .bilateral,
    };

    // Before expiration
    try std.testing.expect(!edge.isExpired(1706651999));

    // After expiration
    try std.testing.expect(edge.isExpired(1706652001));

    // No expiration (0)
    const no_expire = TrustEdge{
        .target_idx = 1,
        .level = .full,
        .expires_at = 0,
        .visibility = .bilateral,
    };
    try std.testing.expect(!no_expire.isExpired(9999999999));
}
