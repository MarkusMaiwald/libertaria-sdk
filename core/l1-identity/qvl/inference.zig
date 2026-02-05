//! RFC-0120 Extension: Loopy Belief Propagation
//!
//! Bayesian inference over the trust DAG for:
//! - Edge weight estimation under uncertainty
//! - Probabilistic betrayal detection (integrates with Bellman-Ford)
//! - Robust anomaly scoring under partial visibility (eclipse attacks)
//!
//! Design: Treat DAG as factor graph; nodes send belief messages
//! until convergence (delta < epsilon). Output: per-node anomaly scores.

const std = @import("std");
const time = @import("time");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskGraph = types.RiskGraph;
const RiskEdge = types.RiskEdge;
const AnomalyScore = types.AnomalyScore;

/// Belief Propagation configuration.
pub const BPConfig = struct {
    /// Maximum iterations before forced stop
    max_iterations: usize = 100,
    /// Convergence threshold (max belief delta)
    epsilon: f64 = 1e-6,
    /// Damping factor to prevent oscillation (0 = no damping, 1 = full damping)
    damping: f64 = 0.5,
    /// Prior belief (uniform assumption)
    prior: f64 = 0.5,
};

/// Result of Belief Propagation inference.
pub const BPResult = struct {
    allocator: std.mem.Allocator,
    /// Final beliefs per node: P(node is trustworthy)
    beliefs: std.AutoHashMapUnmanaged(NodeId, f64),
    /// Anomaly scores derived from beliefs
    anomaly_scores: std.ArrayListUnmanaged(AnomalyScore),
    /// Iterations until convergence
    iterations: usize,
    /// Whether convergence was achieved
    converged: bool,

    pub fn deinit(self: *BPResult) void {
        self.beliefs.deinit(self.allocator);
        self.anomaly_scores.deinit(self.allocator);
    }

    /// Get anomaly score for a specific node.
    pub fn getAnomalyScore(self: *const BPResult, node: NodeId) ?f64 {
        // Low belief = high anomaly
        if (self.beliefs.get(node)) |belief| {
            return 1.0 - belief;
        }
        return null;
    }

    /// Get all nodes with anomaly score above threshold.
    pub fn getAnomalousNodes(self: *const BPResult, threshold: f64, allocator: std.mem.Allocator) ![]AnomalyScore {
        var result = std.ArrayListUnmanaged(AnomalyScore){};

        for (self.anomaly_scores.items) |score| {
            if (score.score >= threshold) {
                try result.append(allocator, score);
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

/// Run Loopy Belief Propagation on the trust graph.
///
/// Algorithm:
/// 1. Initialize all beliefs to prior (0.5 = uncertain).
/// 2. For each iteration:
///    a. Compute messages from edges (influence of neighbors).
///    b. Update beliefs based on incoming messages.
///    c. Check for convergence.
/// 3. Convert low beliefs to anomaly scores.
pub fn runInference(
    graph: *const RiskGraph,
    config: BPConfig,
    allocator: std.mem.Allocator,
) !BPResult {
    const n = graph.nodeCount();
    if (n == 0) {
        return BPResult{
            .allocator = allocator,
            .beliefs = .{},
            .anomaly_scores = .{},
            .iterations = 0,
            .converged = true,
        };
    }

    // Initialize beliefs to prior
    var beliefs = std.AutoHashMapUnmanaged(NodeId, f64){};
    var new_beliefs = std.AutoHashMapUnmanaged(NodeId, f64){};
    defer new_beliefs.deinit(allocator);

    for (graph.nodes.items) |node| {
        try beliefs.put(allocator, node, config.prior);
        try new_beliefs.put(allocator, node, config.prior);
    }

    // Message storage: edge -> belief contribution
    var messages = std.AutoHashMapUnmanaged(usize, f64){}; // edge_idx -> message
    defer messages.deinit(allocator);

    for (0..graph.edgeCount()) |edge_idx| {
        try messages.put(allocator, edge_idx, config.prior);
    }

    var iteration: usize = 0;
    var converged = false;

    while (iteration < config.max_iterations) : (iteration += 1) {
        var max_delta: f64 = 0.0;

        // Step 1: Compute messages from each edge
        for (graph.edges.items, 0..) |edge, edge_idx| {
            const sender_belief = beliefs.get(edge.from) orelse config.prior;

            // Message: sender's belief modulated by edge risk
            // High risk (negative) = low trust propagation
            // Low risk (positive) = high trust propagation
            const risk_factor = (1.0 - @abs(edge.risk)) * @as(f64, if (edge.risk >= 0) 1.0 else 0.5);
            const new_msg = sender_belief * risk_factor;

            const old_msg = messages.get(edge_idx) orelse config.prior;
            // Apply damping
            const damped_msg = config.damping * old_msg + (1.0 - config.damping) * new_msg;
            try messages.put(allocator, edge_idx, damped_msg);
        }

        // Step 2: Update beliefs based on incoming messages
        for (graph.nodes.items) |node| {
            var incoming_sum: f64 = 0.0;
            var incoming_count: usize = 0;

            // Find all edges TO this node
            for (graph.edges.items, 0..) |edge, edge_idx| {
                if (edge.to == node) {
                    incoming_sum += messages.get(edge_idx) orelse config.prior;
                    incoming_count += 1;
                }
            }

            const old_belief = beliefs.get(node) orelse config.prior;
            const new_belief = if (incoming_count > 0)
                incoming_sum / @as(f64, @floatFromInt(incoming_count))
            else
                config.prior;

            // Apply damping
            const damped_belief = config.damping * old_belief + (1.0 - config.damping) * new_belief;
            // Clamp to [0, 1]
            const clamped_belief = @max(0.0, @min(1.0, damped_belief));
            try new_beliefs.put(allocator, node, clamped_belief);

            const delta = @abs(clamped_belief - old_belief);
            max_delta = @max(max_delta, delta);
        }

        // Copy new beliefs to beliefs
        var it = new_beliefs.iterator();
        while (it.next()) |entry| {
            try beliefs.put(allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        // Check convergence
        if (max_delta < config.epsilon) {
            converged = true;
            break;
        }
    }

    // Step 3: Convert beliefs to anomaly scores
    var anomaly_scores = std.ArrayListUnmanaged(AnomalyScore){};
    for (graph.nodes.items) |node| {
        const belief = beliefs.get(node) orelse config.prior;
        const score = 1.0 - belief; // Low belief = high anomaly
        if (score > 0.3) { // Only track notable anomalies
            try anomaly_scores.append(allocator, .{
                .node = node,
                .score = score,
                .reason = .bp_divergence,
            });
        }
    }

    return BPResult{
        .allocator = allocator,
        .beliefs = beliefs,
        .anomaly_scores = anomaly_scores,
        .iterations = iteration,
        .converged = converged,
    };
}

/// Update edge risks in graph based on BP beliefs.
/// This feeds BP output into Bellman-Ford for "probabilistic betrayal detection".
pub fn updateGraphFromBP(
    graph: *RiskGraph,
    result: *const BPResult,
) void {
    for (graph.edges.items) |*edge| {
        const from_belief = result.beliefs.get(edge.from) orelse 0.5;
        const to_belief = result.beliefs.get(edge.to) orelse 0.5;

        // Modulate risk by average belief
        const avg_belief = (from_belief + to_belief) / 2.0;
        edge.risk = edge.risk * avg_belief;
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "BP: Converges on clean graph" {
    const allocator = std.testing.allocator;
    var graph = types.RiskGraph.init(allocator);
    defer graph.deinit();

    // Simple chain: A -> B -> C (all positive)
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.8, .timestamp = time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = time.SovereignTimestamp.fromSeconds(0, .system_boot) });
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = 0.7, .timestamp = time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = time.SovereignTimestamp.fromSeconds(0, .system_boot) });

    var result = try runInference(&graph, .{}, allocator);
    defer result.deinit();

    try std.testing.expect(result.converged);
    try std.testing.expect(result.iterations < 100);
}

test "BP: Detects suspicious node" {
    const allocator = std.testing.allocator;
    var graph = types.RiskGraph.init(allocator);
    defer graph.deinit();

    // Node 2 has negative edges (suspicious)
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);

    try graph.addEdge(.{ .from = 0, .to = 1, .risk = 0.9, .timestamp = time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 3, .expires_at = time.SovereignTimestamp.fromSeconds(0, .system_boot) });
    try graph.addEdge(.{ .from = 0, .to = 2, .risk = -0.5, .timestamp = time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 1, .expires_at = time.SovereignTimestamp.fromSeconds(0, .system_boot) }); // Betrayal
    try graph.addEdge(.{ .from = 1, .to = 2, .risk = -0.3, .timestamp = time.SovereignTimestamp.fromSeconds(0, .system_boot), .nonce = 0, .level = 1, .expires_at = time.SovereignTimestamp.fromSeconds(0, .system_boot) }); // Betrayal

    var result = try runInference(&graph, .{ .max_iterations = 50 }, allocator);
    defer result.deinit();

    // Node 2 should have lower belief (higher anomaly)
    const score_2 = result.getAnomalyScore(2);
    const score_0 = result.getAnomalyScore(0);
    try std.testing.expect(score_2 != null);
    try std.testing.expect(score_0 != null);
    // Score 2 should be higher (more anomalous) than score 0
    try std.testing.expect(score_2.? >= score_0.?);
}

test "BP: Empty graph" {
    const allocator = std.testing.allocator;
    var graph = types.RiskGraph.init(allocator);
    defer graph.deinit();

    var result = try runInference(&graph, .{}, allocator);
    defer result.deinit();

    try std.testing.expect(result.converged);
    try std.testing.expectEqual(result.iterations, 0);
}
