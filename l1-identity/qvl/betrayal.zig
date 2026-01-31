//! RFC-0120 Extension: Bellman-Ford Betrayal Detection
//!
//! Detects negative cycles in the trust graph, which indicate:
//! - Collusion rings (Sybil attacks)
//! - Decade-level betrayals (cascading trust decay)
//! - Cartel behavior (coordinated false vouches)
//!
//! Complexity: O(|V| × |E|) with early exit optimization.

const std = @import("std");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskGraph = types.RiskGraph;
const RiskEdge = types.RiskEdge;
const AnomalyScore = types.AnomalyScore;

/// Result of Bellman-Ford betrayal detection.
pub const BellmanFordResult = struct {
    allocator: std.mem.Allocator,
    /// Shortest distances from source (accounting for negative edges)
    distances: std.AutoHashMapUnmanaged(NodeId, f64),
    /// Predecessor map for path reconstruction
    predecessors: std.AutoHashMapUnmanaged(NodeId, ?NodeId),
    /// Detected betrayal cycles (negative cycles)
    betrayal_cycles: std.ArrayListUnmanaged([]NodeId),

    pub fn deinit(self: *BellmanFordResult) void {
        self.distances.deinit(self.allocator);
        self.predecessors.deinit(self.allocator);
        for (self.betrayal_cycles.items) |cycle| {
            self.allocator.free(cycle);
        }
        self.betrayal_cycles.deinit(self.allocator);
    }

    /// Compute anomaly score based on detected cycles.
    /// Score is normalized to [0, 1].
    pub fn computeAnomalyScore(self: *const BellmanFordResult) f64 {
        if (self.betrayal_cycles.items.len == 0) return 0.0;

        var total_risk: f64 = 0.0;
        for (self.betrayal_cycles.items) |cycle| {
            // Cycle severity = length × base weight
            total_risk += @as(f64, @floatFromInt(cycle.len)) * 0.2;
        }

        // Normalize: cap at 1.0
        return @min(1.0, total_risk);
    }

    /// Get nodes involved in any betrayal cycle.
    pub fn getCompromisedNodes(self: *const BellmanFordResult, allocator: std.mem.Allocator) ![]NodeId {
        var seen = std.AutoHashMapUnmanaged(NodeId, void){};
        defer seen.deinit(allocator);

        for (self.betrayal_cycles.items) |cycle| {
            for (cycle) |node| {
                try seen.put(allocator, node, {});
            }
        }

        var result = try allocator.alloc(NodeId, seen.count());
        var i: usize = 0;
        var it = seen.keyIterator();
        while (it.next()) |key| {
            result[i] = key.*;
            i += 1;
        }
        return result;
    }
};

/// Run Bellman-Ford from source, detecting negative cycles (betrayal rings).
///
/// Algorithm:
/// 1. Relax all edges |V|-1 times.
/// 2. On |V|th pass: If any edge still improves → negative cycle exists.
/// 3. Trace cycle via predecessor map.
pub fn detectBetrayal(
    graph: *const RiskGraph,
    source: NodeId,
    allocator: std.mem.Allocator,
) !BellmanFordResult {
    const n = graph.nodeCount();
    if (n == 0) {
        return BellmanFordResult{
            .allocator = allocator,
            .distances = .{},
            .predecessors = .{},
            .betrayal_cycles = .{},
        };
    }

    var dist = std.AutoHashMapUnmanaged(NodeId, f64){};
    var prev = std.AutoHashMapUnmanaged(NodeId, ?NodeId){};

    // Initialize distances
    for (graph.nodes.items) |node| {
        try dist.put(allocator, node, std.math.inf(f64));
        try prev.put(allocator, node, null);
    }
    try dist.put(allocator, source, 0.0);

    // Relax edges |V|-1 times
    for (0..n - 1) |_| {
        var improved = false;

        for (graph.edges.items) |edge| {
            const d_from = dist.get(edge.from) orelse continue;
            if (d_from == std.math.inf(f64)) continue;

            const d_to = dist.get(edge.to) orelse std.math.inf(f64);
            const new_dist = d_from + edge.risk;

            if (new_dist < d_to) {
                try dist.put(allocator, edge.to, new_dist);
                try prev.put(allocator, edge.to, edge.from);
                improved = true;
            }
        }

        if (!improved) break; // Early exit: no more improvements
    }

    // Detect negative cycles (betrayal rings)
    var cycles = std.ArrayListUnmanaged([]NodeId){};
    var in_cycle = std.AutoHashMapUnmanaged(NodeId, bool){};
    defer in_cycle.deinit(allocator);

    for (graph.edges.items) |edge| {
        const d_from = dist.get(edge.from) orelse continue;
        if (d_from == std.math.inf(f64)) continue;

        const d_to = dist.get(edge.to) orelse continue;

        if (d_from + edge.risk < d_to) {
            // Negative cycle detected; trace it
            if (in_cycle.get(edge.to)) |_| continue; // Already traced

            const cycle = try traceCycle(edge.to, &prev, allocator);
            if (cycle.len > 0) {
                for (cycle) |node| {
                    try in_cycle.put(allocator, node, true);
                }
                try cycles.append(allocator, cycle);
            }
        }
    }

    return BellmanFordResult{
        .allocator = allocator,
        .distances = dist,
        .predecessors = prev,
        .betrayal_cycles = cycles,
    };
}

/// Trace a cycle starting from a node in a negative cycle.
fn traceCycle(
    start: NodeId,
    prev: *std.AutoHashMapUnmanaged(NodeId, ?NodeId),
    allocator: std.mem.Allocator,
) ![]NodeId {
    var visited = std.AutoHashMapUnmanaged(NodeId, usize){};
    defer visited.deinit(allocator);

    var path = std.ArrayListUnmanaged(NodeId){};
    defer path.deinit(allocator);

    var current: ?NodeId = start;
    var idx: usize = 0;

    // Walk backward until we hit a repeat (cycle entry)
    while (current) |curr| {
        if (visited.get(curr)) |cycle_start_idx| {
            // Found cycle; extract it
            const cycle_len = idx - cycle_start_idx;
            if (cycle_len == 0) return &[_]NodeId{};

            const cycle = try allocator.alloc(NodeId, cycle_len);
            @memcpy(cycle, path.items[cycle_start_idx..idx]);
            return cycle;
        }

        try visited.put(allocator, curr, idx);
        try path.append(allocator, curr);

        current = if (prev.get(curr)) |p| p else null;
        idx += 1;

        if (idx > 10000) return error.CycleTooLong; // Safety limit
    }

    return &[_]NodeId{}; // No cycle found
}

// ============================================================================
// TESTS
// ============================================================================

test "Bellman-Ford: No betrayal in clean graph" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // A -> B -> C (all positive)
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.5, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.3, .entropy_stamp = 0, .level = 3, .expires_at = 0 });

    var result = try detectBetrayal(&graph, 0, allocator);
    defer result.deinit();

    try std.testing.expectEqual(result.betrayal_cycles.items.len, 0);
    try std.testing.expectEqual(result.computeAnomalyScore(), 0.0);
}

test "Bellman-Ford: Detect negative cycle (betrayal ring)" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // Triangle: A -> B -> C -> A with negative total weight
    // A --0.2-> B --0.2-> C ---(-0.8)--> A = total -0.4 (negative)
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.2, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.2, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 2, .to = 0, .risk = -0.8, .entropy_stamp = 0, .level = 1, .expires_at = 0 }); // Betrayal!

    var result = try detectBetrayal(&graph, 0, allocator);
    defer result.deinit();

    try std.testing.expect(result.betrayal_cycles.items.len > 0);
    try std.testing.expect(result.computeAnomalyScore() > 0.0);
}

test "Bellman-Ford: Sybil ring detection (5-node cartel)" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // 5-node ring with slight negative total
    for (0..5) |i| {
        try graph.addNode(@intCast(i));
    }

    // Each edge: 0.1 vouch, but one edge -0.6 betrayal
    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.1, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.1, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 2, .to = 3, .risk = 0.1, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 3, .to = 4, .risk = 0.1, .entropy_stamp = 0, .level = 3, .expires_at = 0 });
    try graph.addEdge(.{ .from = 4, .to = 0, .risk = -0.6, .entropy_stamp = 0, .level = 1, .expires_at = 0 }); // Betrayal closes ring

    var result = try detectBetrayal(&graph, 0, allocator);
    defer result.deinit();

    try std.testing.expect(result.betrayal_cycles.items.len > 0);

    const compromised = try result.getCompromisedNodes(allocator);
    defer allocator.free(compromised);
    try std.testing.expect(compromised.len >= 3); // At least 3 nodes in cycle
}
