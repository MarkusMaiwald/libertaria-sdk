//! QVL FFI - C ABI Exports for L2 Integration
//!
//! Provides C-compatible interface for:
//! - Trust scoring
//! - Proof-of-Path verification
//! - Betrayal detection (Bellman-Ford)
//! - Graph mutations
//!
//! Thread Safety: Single-threaded only (initial version)

const std = @import("std");
const qvl = @import("qvl.zig");
const pop_mod = @import("proof_of_path.zig");
const trust_graph = @import("trust_graph.zig");
const time = @import("time");
const slash = @import("slash");

const RiskGraph = qvl.types.RiskGraph;
const RiskEdge = qvl.types.RiskEdge;
const ReputationMap = qvl.pop.ReputationMap;
const ProofOfPath = pop_mod.ProofOfPath;
const PathVerdict = pop_mod.PathVerdict;
const SovereignTimestamp = time.SovereignTimestamp;

// ============================================================================
// OPAQUE CONTEXT
// ============================================================================

/// Opaque handle for QVL context (hides Zig internals)
pub const QvlContext = struct {
    allocator: std.mem.Allocator,
    risk_graph: RiskGraph,
    reputation: ReputationMap,
    trust_graph: trust_graph.CompactTrustGraph,
};

// ============================================================================
// C ABI TYPES
// ============================================================================

pub const PopVerdict = enum(c_int) {
    valid = 0,
    invalid_endpoints = 1,
    broken_link = 2,
    revoked = 3,
    replay = 4,
};

pub const AnomalyReason = enum(u8) {
    none = 0,
    negative_cycle = 1,
    low_coverage = 2,
    bp_divergence = 3,
};

pub const AnomalyScore = extern struct {
    node: u32,
    score: f64, // 0.0-1.0
    reason: u8, // AnomalyReason enum
};

pub const RiskEdgeC = extern struct {
    from: u32,
    to: u32,
    risk: f64,
    timestamp_ns: u64,
    nonce: u64,
    level: u8,
    expires_at_ns: u64,
};

// ============================================================================
// CONTEXT MANAGEMENT
// ============================================================================

/// Initialize QVL context
/// Returns NULL on allocation failure
export fn qvl_init() callconv(.c) ?*QvlContext {
    // Use C allocator for FFI (heap allocations)
    const allocator = std.heap.c_allocator;

    const ctx = allocator.create(QvlContext) catch return null;
    const default_root: [32]u8 = [_]u8{0} ** 32;
    ctx.* = .{
        .allocator = allocator,
        .risk_graph = RiskGraph.init(allocator),
        .reputation = ReputationMap.init(allocator),
        .trust_graph = trust_graph.CompactTrustGraph.init(allocator, default_root, .{}) catch {
            allocator.destroy(ctx);
            return null;
        },
    };

    return ctx;
}

/// Cleanup and free QVL context
export fn qvl_deinit(ctx: ?*QvlContext) callconv(.c) void {
    const context = ctx orelse return;
    context.risk_graph.deinit();
    context.reputation.deinit();
    context.trust_graph.deinit();
    context.allocator.destroy(context);
}

// ============================================================================
// TRUST SCORING
// ============================================================================

/// Get trust score for a DID
/// Returns -1.0 on error (invalid DID, not found, etc.)
export fn qvl_get_trust_score(
    ctx: ?*QvlContext,
    did: [*c]const u8,
    did_len: usize,
) callconv(.c) f64 {
    const context = ctx orelse return -1.0;
    if (did_len != 32) return -1.0; // DID must be 32 bytes

    const did_bytes = did[0..did_len];
    var did_array: [32]u8 = undefined;
    @memcpy(&did_array, did_bytes);

    // Hash DID to NodeId (simplified; real impl would use node_map)
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(&did_array);
    const node_id: u32 = @truncate(hasher.final());

    return context.reputation.get(node_id);
}

/// Get reputation score for a NodeId
/// Returns -1.0 on error
export fn qvl_get_reputation(ctx: ?*QvlContext, node_id: u32) callconv(.c) f64 {
    const context = ctx orelse return -1.0;
    return context.reputation.get(node_id);
}

// ============================================================================
// PROOF-OF-PATH
// ============================================================================

/// Verify a serialized PoP proof
export fn qvl_verify_pop(
    ctx: ?*QvlContext,
    proof_bytes: [*c]const u8,
    proof_len: usize,
    sender_did: [*c]const u8,
    receiver_did: [*c]const u8,
) callconv(.c) PopVerdict {
    const context = ctx orelse return .invalid_endpoints;

    // Deserialize proof
    const proof_slice = proof_bytes[0..proof_len];
    var proof = ProofOfPath.deserialize(context.allocator, proof_slice) catch {
        return .invalid_endpoints;
    };
    defer proof.deinit();

    // Copy DIDs
    var sender: [32]u8 = undefined;
    var receiver: [32]u8 = undefined;
    @memcpy(&sender, sender_did[0..32]);
    @memcpy(&receiver, receiver_did[0..32]);

    // Verify
    const verdict = proof.verify(receiver, sender, &context.trust_graph);

    // Convert to C enum
    return switch (verdict) {
        .valid => .valid,
        .invalid_endpoints => .invalid_endpoints,
        .broken_link => .broken_link,
        .revoked => .revoked,
        .replay => .replay,
        else => .invalid_endpoints, // Catch-all for future enum additions
    };
}

// ============================================================================
// BETRAYAL DETECTION
// ============================================================================

/// Run Bellman-Ford betrayal detection from source node
/// Returns anomaly score (0.0 = clean, 0.9+ = critical)
export fn qvl_detect_betrayal(
    ctx: ?*QvlContext,
    source_node: u32,
) callconv(.c) AnomalyScore {
    const context = ctx orelse return .{ .node = 0, .score = 0.0, .reason = @intFromEnum(AnomalyReason.none) };

    var result = qvl.betrayal.detectBetrayal(
        &context.risk_graph,
        source_node,
        context.allocator,
    ) catch {
        return .{ .node = 0, .score = 0.0, .reason = @intFromEnum(AnomalyReason.none) };
    };
    defer result.deinit();

    if (result.betrayal_cycles.items.len > 0) {
        // Betrayal detected - compute anomaly score
        const score = result.computeAnomalyScore();
        return .{
            .node = source_node,
            .score = score,
            .reason = @intFromEnum(AnomalyReason.negative_cycle),
        };
    }

    return .{ .node = source_node, .score = 0.0, .reason = @intFromEnum(AnomalyReason.none) };
}

// ============================================================================
// GRAPH MUTATIONS
// ============================================================================

/// Add trust edge to risk graph
/// Returns 0 on success, non-zero on error
export fn qvl_add_trust_edge(
    ctx: ?*QvlContext,
    edge_c: [*c]const RiskEdgeC,
) callconv(.c) c_int {
    const context = ctx orelse return -1;
    const edge_ptr = edge_c orelse return -1;
    const edge_val = edge_ptr.*;

    const edge = RiskEdge{
        .from = edge_val.from,
        .to = edge_val.to,
        .risk = edge_val.risk,
        .timestamp = SovereignTimestamp.fromNanoseconds(edge_val.timestamp_ns, .unix_1970),
        .nonce = edge_val.nonce,
        .level = edge_val.level,
        .expires_at = SovereignTimestamp.fromNanoseconds(edge_val.expires_at_ns, .unix_1970),
    };

    context.risk_graph.addEdge(edge) catch return -2;
    return 0;
}

/// Revoke trust edge
/// Returns 0 on success, non-zero on error (not found, etc.)
export fn qvl_revoke_trust_edge(
    ctx: ?*QvlContext,
    from: u32,
    to: u32,
) callconv(.c) c_int {
    const context = ctx orelse return -1;

    // Find and remove edge
    var i: usize = 0;
    while (i < context.risk_graph.edges.items.len) : (i += 1) {
        const edge = &context.risk_graph.edges.items[i];
        if (edge.from == from and edge.to == to) {
            _ = context.risk_graph.edges.swapRemove(i);
            return 0;
        }
    }

    return -2; // Not found
}

/// Issue a SlashSignal for a detected betrayal
/// Returns 0 on success, < 0 on error
/// If 'out_signal' is non-null, writes serialized signal (82 bytes)
export fn qvl_issue_slash_signal(
    ctx: ?*QvlContext,
    target_did: [*c]const u8,
    reason: u8,
    out_signal: [*c]u8,
) callconv(.c) c_int {
    _ = ctx; // Context not strictly needed for constructing signal, but good for future validation
    if (target_did == null) return -2;

    var did: [32]u8 = undefined;
    @memcpy(&did, target_did[0..32]);

    const signal = slash.SlashSignal{
        .target_did = did,
        .reason = @enumFromInt(reason),
        .punishment = .Quarantine, // Default to Quarantine
        .evidence_hash = [_]u8{0} ** 32, // TODO: Hash actual evidence
        .timestamp = std.time.timestamp(),
        .nonce = 0,
    };

    if (out_signal != null) {
        const bytes = signal.serializeForSigning();
        @memcpy(out_signal[0..82], &bytes);
    }

    return 0;
}

// ============================================================================
// TESTS (C ABI validation)
// ============================================================================

test "FFI: context lifecycle" {
    const ctx = qvl_init();
    try std.testing.expect(ctx != null);
    qvl_deinit(ctx);
}

test "FFI: trust scoring" {
    const ctx = qvl_init() orelse return error.InitFailed;
    defer qvl_deinit(ctx);

    const score = qvl_get_reputation(ctx, 42);
    try std.testing.expectEqual(score, 0.5); // Default neutral
}

test "FFI: add edge" {
    const ctx = qvl_init() orelse return error.InitFailed;
    defer qvl_deinit(ctx);

    const edge = RiskEdgeC{
        .from = 0,
        .to = 1,
        .risk = 0.5,
        .timestamp_ns = 1000,
        .nonce = 0,
        .level = 3,
        .expires_at_ns = 2000,
    };

    const result = qvl_add_trust_edge(ctx, &edge);
    try std.testing.expectEqual(result, 0);
}
