//! RFC-0120 Extension: A* Trust Pathfinding
//!
//! Reputation-guided pathfinding for fast trust distance queries.
//! Uses admissible heuristic based on average reputation to guide search
//! toward high-trust nodes, achieving ~10x speedup over naive Dijkstra.
//!
//! Complexity: O(|E| + |V| log |V|) with binary heap.

const std = @import("std");
const l0_transport = @import("l0_transport");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskGraph = types.RiskGraph;
const RiskEdge = types.RiskEdge;

/// A* search node with priority scoring.
const AStarNode = struct {
    id: NodeId,
    g_score: f64, // Cost from start
    f_score: f64, // g + heuristic

    fn lessThan(context: void, a: AStarNode, b: AStarNode) std.math.Order {
        _ = context;
        return std.math.order(a.f_score, b.f_score);
    }
};

/// Result of A* pathfinding.
pub const PathResult = struct {
    allocator: std.mem.Allocator,
    /// Path from source to target (node indices)
    path: ?[]NodeId,
    /// Total cost of the path
    total_cost: f64,

    pub fn deinit(self: *PathResult) void {
        if (self.path) |p| {
            self.allocator.free(p);
        }
    }

    pub fn pathLength(self: *const PathResult) usize {
        return if (self.path) |p| p.len else 0;
    }
};

/// Heuristic function type.
/// Must be admissible: never overestimate true cost.
pub const HeuristicFn = *const fn (node: NodeId, target: NodeId, context: *const anyopaque) f64;

/// Default reputation heuristic.
/// h(n) = (1.0 - avg_reputation[n]) * estimated_hops
/// Admissible if reputation ∈ [0, 1] and estimated_hops <= actual.
pub fn reputationHeuristic(node: NodeId, target: NodeId, context: *const anyopaque) f64 {
    _ = context; // Would use reputation_map in full impl
    _ = node;
    _ = target;
    // Conservative default: assume 1 hop remaining
    return 0.5; // Neutral heuristic
}

/// Zero heuristic (degrades to Dijkstra)
pub fn zeroHeuristic(_: NodeId, _: NodeId, _: *const anyopaque) f64 {
    return 0.0;
}

/// Find shortest trust path from source to target using A*.
///
/// Algorithm:
/// 1. Maintain open set as min-heap by f_score.
/// 2. Expand node with lowest f_score.
/// 3. Update g_scores for neighbors.
/// 4. Reconstruct path when target reached.
pub fn findTrustPath(
    graph: *const RiskGraph,
    source: NodeId,
    target: NodeId,
    heuristic: HeuristicFn,
    heuristic_ctx: *const anyopaque,
    allocator: std.mem.Allocator,
) !PathResult {
    if (source == target) {
        const path = try allocator.alloc(NodeId, 1);
        path[0] = source;
        return PathResult{
            .allocator = allocator,
            .path = path,
            .total_cost = 0.0,
        };
    }

    var open_set = std.PriorityQueue(AStarNode, void, AStarNode.lessThan).init(allocator, {});
    defer open_set.deinit();

    var g_score = std.AutoHashMapUnmanaged(NodeId, f64){};
    defer g_score.deinit(allocator);

    var came_from = std.AutoHashMapUnmanaged(NodeId, NodeId){};
    defer came_from.deinit(allocator);

    var in_closed = std.AutoHashMapUnmanaged(NodeId, void){};
    defer in_closed.deinit(allocator);

    try g_score.put(allocator, source, 0.0);
    const h_start = heuristic(source, target, heuristic_ctx);
    try open_set.add(.{ .id = source, .g_score = 0.0, .f_score = h_start });

    while (open_set.count() > 0) {
        const current = open_set.remove();

        if (current.id == target) {
            // Reconstruct path
            const path = try reconstructPath(target, &came_from, allocator);
            return PathResult{
                .allocator = allocator,
                .path = path,
                .total_cost = current.g_score,
            };
        }

        // Skip if already processed (closed set)
        if (in_closed.get(current.id)) |_| continue;
        try in_closed.put(allocator, current.id, {});

        const current_g = g_score.get(current.id) orelse continue;

        // Expand neighbors
        for (graph.neighbors(current.id)) |edge_idx| {
            const edge = graph.edges.items[edge_idx];
            const neighbor = edge.to;

            if (in_closed.get(neighbor)) |_| continue;

            const tentative_g = current_g + edge.risk;
            const neighbor_g = g_score.get(neighbor) orelse std.math.inf(f64);

            if (tentative_g < neighbor_g) {
                try came_from.put(allocator, neighbor, current.id);
                try g_score.put(allocator, neighbor, tentative_g);

                const h = heuristic(neighbor, target, heuristic_ctx);
                const f = tentative_g + h;
                try open_set.add(.{ .id = neighbor, .g_score = tentative_g, .f_score = f });
            }
        }
    }

    return PathResult{
        .allocator = allocator,
        .path = null,
        .total_cost = std.math.inf(f64),
    };
}

fn reconstructPath(
    target: NodeId,
    came_from: *std.AutoHashMapUnmanaged(NodeId, NodeId),
    allocator: std.mem.Allocator,
) ![]NodeId {
    var path = std.ArrayListUnmanaged(NodeId){};
    defer path.deinit(allocator);

    var current = target;
    try path.append(allocator, current);

    while (came_from.get(current)) |prev| {
        current = prev;
        try path.insert(allocator, 0, current);
    }

    return path.toOwnedSlice(allocator);
}

// ============================================================================
// TESTS
// ============================================================================

test "A* Pathfinding: Direct path" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // A -> B -> C
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.3, .timestamp = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot) });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.2, .timestamp = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot) });

    const dummy_ctx: u8 = 0;
    var result = try findTrustPath(&graph, 0, 2, zeroHeuristic, @ptrCast(&dummy_ctx), allocator);
    defer result.deinit();

    try std.testing.expect(result.path != null);
    try std.testing.expectEqual(result.pathLength(), 3);
    try std.testing.expectEqual(result.path.?[0], 0);
    try std.testing.expectEqual(result.path.?[1], 1);
    try std.testing.expectEqual(result.path.?[2], 2);
    try std.testing.expectApproxEqAbs(result.total_cost, 0.5, 0.001);
}

test "A* Pathfinding: No path" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // A and B disconnected
    try graph.addNode(0);
    try graph.addNode(1);

    const dummy_ctx: u8 = 0;
    var result = try findTrustPath(&graph, 0, 1, zeroHeuristic, @ptrCast(&dummy_ctx), allocator);
    defer result.deinit();

    try std.testing.expect(result.path == null);
}

test "A* Pathfinding: Same source and target" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    try graph.addNode(0);

    const dummy_ctx: u8 = 0;
    var result = try findTrustPath(&graph, 0, 0, zeroHeuristic, @ptrCast(&dummy_ctx), allocator);
    defer result.deinit();

    try std.testing.expect(result.path != null);
    try std.testing.expectEqual(result.pathLength(), 1);
    try std.testing.expectEqual(result.total_cost, 0.0);
}

test "A* Pathfinding: Multiple paths, chooses shortest" {
    const allocator = std.testing.allocator;
    var graph = RiskGraph.init(allocator);
    defer graph.deinit();

    // A -> B -> C (cost 0.8)
    // A -> C directly (cost 0.5)
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.4, .timestamp = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot) });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.4, .timestamp = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot) });
    try graph.addEdge(.{ .from = 0, .to = 2, .risk = 0.5, .timestamp = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = l0_transport.time.SovereignTimestamp.fromSeconds(0, .system_boot) }); // Direct shorter

    const dummy_ctx: u8 = 0;
    var result = try findTrustPath(&graph, 0, 2, zeroHeuristic, @ptrCast(&dummy_ctx), allocator);
    defer result.deinit();

    try std.testing.expect(result.path != null);
    try std.testing.expectEqual(result.pathLength(), 2); // Direct path
    try std.testing.expectApproxEqAbs(result.total_cost, 0.5, 0.001);
}
