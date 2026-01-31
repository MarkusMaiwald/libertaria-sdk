//! QVL Core Types for Advanced Graph Algorithms
//!
//! Extends RFC-0120 TrustEdge with risk scoring for Bellman-Ford.

const std = @import("std");
const time = @import("time");

const SovereignTimestamp = time.SovereignTimestamp;

/// Node identifier (compact u32 index into DID storage)
pub const NodeId = u32;

/// Extended edge with risk scoring for Bellman-Ford algorithms.
/// This is the "in-memory" representation for graph algorithms;
/// the compact TrustEdge remains the wire format.
pub const RiskEdge = struct {
    /// Source node index
    from: NodeId,
    /// Target node index
    to: NodeId,
    /// Risk score: negative = betrayal signal, positive = vouch
    /// Range: [-1.0, 1.0] where:
    ///   -1.0 = Confirmed betrayal (decade-level)
    ///   0.0 = Neutral/unknown
    ///   +1.0 = Maximum trust
    risk: f64,
    /// Temporal anchor for graph ordering (attosecond precision)
    timestamp: SovereignTimestamp,
    /// Nonce for path provenance (L0 sequence tied to trust transition)
    /// Enables: replay protection, exact path reconstruction, routing verification
    nonce: u64,
    /// Original trust level (for path verification)
    level: u8,
    /// Expiration timestamp
    expires_at: SovereignTimestamp,

    pub fn isBetrayal(self: RiskEdge) bool {
        return self.risk < 0.0;
    }

    pub fn isExpired(self: RiskEdge, current_time: SovereignTimestamp) bool {
        return current_time.isAfter(self.expires_at);
    }
};

/// Anomaly score from Bellman-Ford or Belief Propagation.
/// Normalized to [0, 1] where:
///   0.0 = No anomaly
///   0.7+ = P1 Alert (requires investigation)
///   0.9+ = P0 Critical (immediate action)
pub const AnomalyScore = struct {
    node: NodeId,
    score: f64,
    reason: Reason,

    pub const Reason = enum {
        none,
        negative_cycle, // Bellman-Ford
        low_coverage, // Gossip partition
        bp_divergence, // Belief Propagation
        pomcp_reject, // POMCP planning
    };

    pub fn isCritical(self: AnomalyScore) bool {
        return self.score >= 0.9;
    }

    pub fn isAlert(self: AnomalyScore) bool {
        return self.score >= 0.7;
    }
};

/// Graph structure for QVL algorithms.
/// Wraps edges and provides adjacency lookup.
pub const RiskGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayListUnmanaged(NodeId),
    edges: std.ArrayListUnmanaged(RiskEdge),
    /// Adjacency: node -> list of edge indices
    adjacency: std.AutoHashMapUnmanaged(NodeId, std.ArrayListUnmanaged(usize)),

    pub fn init(allocator: std.mem.Allocator) RiskGraph {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .edges = .{},
            .adjacency = .{},
        };
    }

    pub fn deinit(self: *RiskGraph) void {
        self.nodes.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        var it = self.adjacency.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.adjacency.deinit(self.allocator);
    }

    pub fn addNode(self: *RiskGraph, node: NodeId) !void {
        try self.nodes.append(self.allocator, node);
    }

    pub fn addEdge(self: *RiskGraph, edge: RiskEdge) !void {
        const edge_idx = self.edges.items.len;
        try self.edges.append(self.allocator, edge);

        // Update adjacency
        const entry = try self.adjacency.getOrPut(self.allocator, edge.from);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{};
        }
        try entry.value_ptr.append(self.allocator, edge_idx);
    }

    pub fn neighbors(self: *const RiskGraph, node: NodeId) []const usize {
        if (self.adjacency.get(node)) |edges| {
            return edges.items;
        }
        return &[_]usize{};
    }

    pub fn nodeCount(self: *const RiskGraph) usize {
        return self.nodes.items.len;
    }

    pub fn edgeCount(self: *const RiskGraph) usize {
        return self.edges.items.len;
    }
};

test "RiskGraph: basic operations" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    const ts = SovereignTimestamp.fromSeconds(0, .system_boot);
    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.5, .timestamp = ts, .nonce = 0, .level = 3, .expires_at = ts });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = -0.3, .timestamp = ts, .nonce = 1, .level = 2, .expires_at = ts }); // Betrayal

    try std.testing.expectEqual(graph.nodeCount(), 3);
    try std.testing.expectEqual(graph.edgeCount(), 2);
    try std.testing.expectEqual(graph.neighbors(0).len, 1);
    try std.testing.expect(graph.edges.items[1].isBetrayal());
}
