//! RFC-0120 Extension: Aleph-Style Gossip
//!
//! Probabilistic flooding for trust signal propagation.
//! Handles intermittent connectivity (Kenya Rule) via:
//! - Erasure-tolerant message references
//! - Coverage tracking for partition detection
//! - Entropy-stamped messages for replay protection
//!
//! Design: Each gossip message references k random prior messages,
//! creating a DAG structure resilient to packet loss.

const std = @import("std");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskGraph = types.RiskGraph;

/// Gossip message with DAG references.
pub const GossipMessage = struct {
    /// Unique message ID (hash of content + entropy)
    id: u64,
    /// Sender node index
    sender: NodeId,
    /// References to prior messages (DAG structure)
    refs: []const u64,
    /// Payload type
    msg_type: MessageType,
    /// Entropy stamp for temporal ordering (RFC-0100)
    entropy_stamp: u64,
    /// Message payload
    payload: []const u8,

    pub const MessageType = enum(u8) {
        trust_vouch = 0, // New trust edge
        trust_revoke = 1, // Edge removal
        reputation_update = 2, // Score change
        heartbeat = 3, // Liveness check
    };

    /// Compute message ID from content.
    pub fn computeId(sender: NodeId, entropy_stamp: u64, payload: []const u8) u64 {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&sender));
        hasher.update(std.mem.asBytes(&entropy_stamp));
        hasher.update(payload);
        return hasher.final();
    }
};

/// Gossip state tracker for a node.
pub const GossipState = struct {
    allocator: std.mem.Allocator,
    /// Recent message IDs (for reference sampling)
    recent_messages: std.ArrayListUnmanaged(u64),
    /// Seen message IDs (for deduplication)
    seen_messages: std.AutoHashMapUnmanaged(u64, void),
    /// Coverage tracking: which nodes have we heard from recently
    heard_from: std.AutoHashMapUnmanaged(NodeId, u64), // node -> last_entropy_stamp
    /// Configuration
    config: Config,

    pub const Config = struct {
        /// Number of prior messages to reference
        ref_k: usize = 3,
        /// Maximum recent messages to track
        max_recent: usize = 100,
        /// Probability of forwarding (1.0 - drop_prob)
        forward_prob: f64 = 0.7,
        /// Coverage window (entropy stamp delta)
        coverage_window: u64 = 60_000_000_000, // 60 seconds in nanoseconds
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) GossipState {
        return .{
            .allocator = allocator,
            .recent_messages = .{},
            .seen_messages = .{},
            .heard_from = .{},
            .config = config,
        };
    }

    pub fn deinit(self: *GossipState) void {
        self.recent_messages.deinit(self.allocator);
        self.seen_messages.deinit(self.allocator);
        self.heard_from.deinit(self.allocator);
    }

    /// Check if message is new (not seen before).
    pub fn isNewMessage(self: *GossipState, msg_id: u64) !bool {
        if (self.seen_messages.get(msg_id)) |_| {
            return false;
        }
        try self.seen_messages.put(self.allocator, msg_id, {});
        return true;
    }

    /// Record a message as seen.
    pub fn recordMessage(self: *GossipState, msg: *const GossipMessage) !void {
        // Add to seen set
        try self.seen_messages.put(self.allocator, msg.id, {});

        // Add to recent messages (for future refs)
        if (self.recent_messages.items.len >= self.config.max_recent) {
            _ = self.recent_messages.orderedRemove(0);
        }
        try self.recent_messages.append(self.allocator, msg.id);

        // Update heard_from
        try self.heard_from.put(self.allocator, msg.sender, msg.entropy_stamp);
    }

    /// Sample k random references from recent messages.
    pub fn sampleRefs(self: *GossipState, rand: std.Random, allocator: std.mem.Allocator) ![]u64 {
        const k = @min(self.config.ref_k, self.recent_messages.items.len);
        if (k == 0) return &[_]u64{};

        var refs = try allocator.alloc(u64, k);
        var selected = std.AutoHashMapUnmanaged(usize, void){};
        defer selected.deinit(allocator);

        var i: usize = 0;
        while (i < k) {
            const idx = rand.intRangeLessThan(usize, 0, self.recent_messages.items.len);
            if (selected.get(idx)) |_| continue;
            try selected.put(allocator, idx, {});
            refs[i] = self.recent_messages.items[idx];
            i += 1;
        }

        return refs;
    }

    /// Compute coverage ratio: fraction of nodes heard from recently.
    pub fn computeCoverage(self: *const GossipState, total_nodes: usize, current_entropy: u64) f64 {
        if (total_nodes == 0) return 1.0;

        var active_count: usize = 0;
        var it = self.heard_from.iterator();
        while (it.next()) |entry| {
            const last_stamp = entry.value_ptr.*;
            if (current_entropy - last_stamp <= self.config.coverage_window) {
                active_count += 1;
            }
        }

        return @as(f64, @floatFromInt(active_count)) / @as(f64, @floatFromInt(total_nodes));
    }
};

/// Gossip result after flooding.
pub const FloodResult = struct {
    /// Number of neighbors that received the message
    sent_count: usize,
    /// Total neighbors attempted
    total_neighbors: usize,
    /// Coverage after flood
    coverage: f64,
};

/// Probabilistic flood of a gossip message to neighbors.
pub fn floodMessage(
    graph: *const RiskGraph,
    sender: NodeId,
    message: *const GossipMessage,
    state: *GossipState,
    rand: std.Random,
    // In real impl, this would be a transport callback
    // send_fn: *const fn(NodeId, []const u8) void,
) FloodResult {
    var sent_count: usize = 0;
    const neighbors = graph.neighbors(sender);

    for (neighbors) |edge_idx| {
        // In real impl: extract neighbor ID and send
        _ = edge_idx; // Will be used when UTCP transport is integrated

        // Probabilistic drop (simulates lossy network)
        if (rand.float(f64) <= state.config.forward_prob) {
            // In real impl: send_fn(neighbor, serialize(message));
            // TODO: Integrate with UTCP transport layer
            sent_count += 1;
        }
    }

    const coverage = state.computeCoverage(graph.nodeCount(), message.entropy_stamp);

    return FloodResult{
        .sent_count = sent_count,
        .total_neighbors = neighbors.len,
        .coverage = coverage,
    };
}

/// Create a new gossip message.
pub fn createMessage(
    sender: NodeId,
    msg_type: GossipMessage.MessageType,
    payload: []const u8,
    entropy_stamp: u64,
    state: *GossipState,
    rand: std.Random,
    allocator: std.mem.Allocator,
) !GossipMessage {
    const refs = try state.sampleRefs(rand, allocator);
    const id = GossipMessage.computeId(sender, entropy_stamp, payload);

    return GossipMessage{
        .id = id,
        .sender = sender,
        .refs = refs,
        .msg_type = msg_type,
        .entropy_stamp = entropy_stamp,
        .payload = payload,
    };
}

// ============================================================================
// TESTS
// ============================================================================

test "GossipState: message deduplication" {
    const allocator = std.testing.allocator;
    var state = GossipState.init(allocator, .{});
    defer state.deinit();

    const msg_id: u64 = 12345;

    // First time: new
    try std.testing.expect(try state.isNewMessage(msg_id));
    // Second time: duplicate
    try std.testing.expect(!(try state.isNewMessage(msg_id)));
}

test "GossipState: coverage tracking" {
    const allocator = std.testing.allocator;
    var state = GossipState.init(allocator, .{ .coverage_window = 1000 });
    defer state.deinit();

    const now: u64 = 5000;

    // Record messages from 2 nodes
    try state.heard_from.put(allocator, 0, now - 500); // Recent
    try state.heard_from.put(allocator, 1, now - 2000); // Stale

    const coverage = state.computeCoverage(3, now);
    // 1 out of 3 nodes heard from recently
    try std.testing.expectApproxEqAbs(coverage, 0.333, 0.01);
}

test "GossipState: reference sampling" {
    const allocator = std.testing.allocator;
    var state = GossipState.init(allocator, .{ .ref_k = 2 });
    defer state.deinit();

    // Add some recent messages
    try state.recent_messages.append(allocator, 100);
    try state.recent_messages.append(allocator, 200);
    try state.recent_messages.append(allocator, 300);

    var prng = std.Random.DefaultPrng.init(42);
    const refs = try state.sampleRefs(prng.random(), allocator);
    defer allocator.free(refs);

    try std.testing.expectEqual(refs.len, 2);
}

test "GossipMessage: ID computation" {
    const id1 = GossipMessage.computeId(0, 1000, "hello");
    const id2 = GossipMessage.computeId(0, 1000, "hello");
    const id3 = GossipMessage.computeId(0, 1001, "hello");

    try std.testing.expectEqual(id1, id2); // Same input, same ID
    try std.testing.expect(id1 != id3); // Different entropy, different ID
}
