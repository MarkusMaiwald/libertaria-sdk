//! QVL + Proof-of-Path Integration
//!
//! Bridges the existing `proof_of_path.zig` (Phase 3C) with the QVL graph engine.
//! Enables:
//! - Reputation scoring from PoP verification
//! - PoP-guided A* heuristic (prefer paths with proven trust)
//! - Real-time trust decay on PoP failures
//!
//! This is where PoP + Reputation become L1's "magic".

const std = @import("std");
const types = @import("types.zig");
const pathfinding = @import("pathfinding.zig");
// Import proof_of_path relative from qvl directory
const pop = @import("../proof_of_path.zig");
const trust_graph = @import("trust_graph");

const NodeId = types.NodeId;
const RiskGraph = types.RiskGraph;
const RiskEdge = types.RiskEdge;
const ProofOfPath = pop.ProofOfPath;
const PathVerdict = pop.PathVerdict;

/// Reputation score derived from PoP verification.
/// Range: [0.0, 1.0]
/// - 1.0 = Perfect PoP verification history
/// - 0.5 = Neutral (new node, no history)
/// - 0.0 = Consistent PoP failures (likely adversarial)
pub const ReputationScore = struct {
    node: NodeId,
    score: f64,
    /// Total PoP verifications attempted
    total_checks: u32,
    /// Successful verifications
    successful_checks: u32,
    /// Last verified timestamp (entropy stamp)
    last_verified: u64,

    pub fn init(node: NodeId) ReputationScore {
        return .{
            .node = node,
            .score = 0.5, // Neutral default
            .total_checks = 0,
            .successful_checks = 0,
            .last_verified = 0,
        };
    }

    /// Update reputation after a PoP verification attempt.
    pub fn update(self: *ReputationScore, verdict: PathVerdict, entropy_stamp: u64) void {
        self.total_checks += 1;
        if (verdict == .valid) {
            self.successful_checks += 1;
            self.last_verified = entropy_stamp;
        }

        // Bayesian update: score = successful / total (with prior weighting)
        const success_rate = @as(f64, @floatFromInt(self.successful_checks)) /
            @as(f64, @floatFromInt(self.total_checks));

        // Apply damping to prevent extreme swings on single failures
        const damping = 0.7;
        self.score = damping * self.score + (1.0 - damping) * success_rate;

        // Clamp to [0, 1]
        self.score = @max(0.0, @min(1.0, self.score));
    }

    /// Decay reputation over time if no recent verifications.
    pub fn decay(self: *ReputationScore, current_entropy: u64, half_life_ns: u64) void {
        const time_since = current_entropy - self.last_verified;
        if (time_since == 0) return;

        // Exponential decay: score *= 0.5^(time_since / half_life)
        const decay_factor = std.math.pow(
            f64,
            0.5,
            @as(f64, @floatFromInt(time_since)) / @as(f64, @floatFromInt(half_life_ns)),
        );
        self.score *= decay_factor;
        self.score = @max(0.0, self.score);
    }
};

/// Reputation map for all nodes in the graph.
pub const ReputationMap = struct {
    allocator: std.mem.Allocator,
    scores: std.AutoHashMapUnmanaged(NodeId, ReputationScore),
    /// Default half-life: 7 days in nanoseconds
    decay_half_life: u64 = 7 * 24 * 3600 * 1_000_000_000,

    pub fn init(allocator: std.mem.Allocator) ReputationMap {
        return .{
            .allocator = allocator,
            .scores = .{},
        };
    }

    pub fn deinit(self: *ReputationMap) void {
        self.scores.deinit(self.allocator);
    }

    /// Get reputation score for a node (default: 0.5 if unknown).
    pub fn get(self: *const ReputationMap, node: NodeId) f64 {
        if (self.scores.get(node)) |score| {
            return score.score;
        }
        return 0.5; // Neutral for unknown nodes
    }

    /// Record a PoP verification result.
    pub fn recordVerification(
        self: *ReputationMap,
        node: NodeId,
        verdict: PathVerdict,
        entropy_stamp: u64,
    ) !void {
        var entry = try self.scores.getOrPut(self.allocator, node);
        if (!entry.found_existing) {
            entry.value_ptr.* = ReputationScore.init(node);
        }
        entry.value_ptr.update(verdict, entropy_stamp);
    }

    /// Decay all reputations based on current time.
    pub fn applyDecay(self: *ReputationMap, current_entropy: u64) void {
        var it = self.scores.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.decay(current_entropy, self.decay_half_life);
        }
    }

    /// Get all nodes with reputation below threshold.
    pub fn getLowReputationNodes(
        self: *const ReputationMap,
        threshold: f64,
        allocator: std.mem.Allocator,
    ) ![]NodeId {
        var result = std.ArrayListUnmanaged(NodeId){};

        var it = self.scores.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.score < threshold) {
                try result.append(allocator, entry.key_ptr.*);
            }
        }

        return result.toOwnedSlice(allocator);
    }
};

/// PoP-aware A* heuristic.
/// Prioritizes paths through high-reputation nodes.
pub fn popReputationHeuristic(
    node: NodeId,
    target: NodeId,
    context: *const anyopaque,
) f64 {
    const rep_map: *const ReputationMap = @ptrCast(@alignCast(context));

    // Base heuristic: assume 1 hop remaining
    const base_cost = 1.0;

    // Reputation penalty: low reputation = higher cost
    const rep = rep_map.get(node);
    const rep_penalty = (1.0 - rep) * 2.0; // Max penalty: 2.0 for rep=0

    _ = target; // Not used in admissible heuristic
    return base_cost + rep_penalty;
}

/// Verify a PoP and update reputation scores.
pub fn verifyAndUpdateReputation(
    proof: *const ProofOfPath,
    expected_receiver: [32]u8,
    expected_sender: [32]u8,
    graph: *const trust_graph.CompactTrustGraph,
    rep_map: *ReputationMap,
    current_entropy: u64,
) PathVerdict {
    const verdict = proof.verify(expected_receiver, expected_sender, graph);

    // Update reputation for the sender
    // (In a full impl, we'd extract NodeId from DID)
    // For now, use a hash of the sender DID as NodeId
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(&expected_sender);
    const sender_id: NodeId = @truncate(hasher.final());

    rep_map.recordVerification(sender_id, verdict, current_entropy) catch {
        // If allocation fails, degrade gracefully (skip reputation update)
    };

    return verdict;
}

/// Initialize RiskGraph edges with reputation-weighted risks.
pub fn populateRiskFromReputation(
    risk_graph: *RiskGraph,
    trust_compact: *const trust_graph.CompactTrustGraph,
    rep_map: *const ReputationMap,
) !void {
    // For each edge in the CompactTrustGraph, add to RiskGraph with risk = (1 - reputation)
    const edges = trust_compact.getAllEdges();

    for (edges) |edge| {
        // Extract NodeIds (would use actual DID->NodeId mapping in full impl)
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(&edge.did);
        const to_id: NodeId = @truncate(hasher.final());

        // Compute risk from reputation
        const rep = rep_map.get(to_id);
        const risk = 1.0 - rep; // High rep = low risk

        const risk_edge = RiskEdge{
            .from = 0, // Would map from trust_compact.root_idx
            .to = to_id,
            .risk = risk,
            .entropy_stamp = 0, // Would extract from edge metadata
            .level = edge.level,
            .expires_at = edge.expires_at orelse 0,
        };

        try risk_graph.addEdge(risk_edge);
    }
}

// ============================================================================
// TESTS
// ============================================================================

test "ReputationScore: initial neutral score" {
    const score = ReputationScore.init(42);
    try std.testing.expectEqual(score.score, 0.5);
    try std.testing.expectEqual(score.total_checks, 0);
}

test "ReputationScore: successful verifications increase score" {
    var score = ReputationScore.init(42);

    score.update(.valid, 1000);
    try std.testing.expect(score.score > 0.5);

    score.update(.valid, 2000);
    score.update(.valid, 3000);
    try std.testing.expect(score.score > 0.75); // Damping prevents rapid convergence
}

test "ReputationScore: failed verifications decrease score" {
    var score = ReputationScore.init(42);

    score.update(.broken_link, 1000);
    try std.testing.expect(score.score < 0.5);

    score.update(.broken_link, 2000);
    try std.testing.expect(score.score < 0.3);
}

test "ReputationScore: decay over time" {
    var score = ReputationScore.init(42);
    score.update(.valid, 1000);
    const initial = score.score;

    // Decay after half-life
    const half_life: u64 = 1000;
    score.decay(1000 + half_life, half_life);

    try std.testing.expect(score.score < initial);
    try std.testing.expectApproxEqAbs(score.score, initial * 0.5, 0.1);
}

test "ReputationMap: get unknown node" {
    const allocator = std.testing.allocator;
    var rep_map = ReputationMap.init(allocator);
    defer rep_map.deinit();

    const score = rep_map.get(999);
    try std.testing.expectEqual(score, 0.5); // Default neutral
}

test "ReputationMap: record verification" {
    const allocator = std.testing.allocator;
    var rep_map = ReputationMap.init(allocator);
    defer rep_map.deinit();

    try rep_map.recordVerification(42, .valid, 1000);
    const score = rep_map.get(42);
    try std.testing.expect(score > 0.5);
}

test "ReputationMap: low reputation nodes" {
    const allocator = std.testing.allocator;
    var rep_map = ReputationMap.init(allocator);
    defer rep_map.deinit();

    try rep_map.recordVerification(1, .valid, 1000);
    try rep_map.recordVerification(2, .broken_link, 1000);
    try rep_map.recordVerification(2, .broken_link, 2000);

    const low_rep = try rep_map.getLowReputationNodes(0.4, allocator);
    defer allocator.free(low_rep);

    try std.testing.expectEqual(low_rep.len, 1);
    try std.testing.expectEqual(low_rep[0], 2);
}
