//! Proof of Path (RFC-0120)
//!
//! "Don't scan the graph. Prove the path."
//!
//! Sender includes O(depth) proof: [Sender->A, A->B, B->Receiver]
//! Receiver verifies in O(depth) checking only adjacent signatures.
//!
//! Enables Kenya-class devices to participate in the trust graph without having a huge database.
//!
//! Wire Format (CBOR-like structure):
//! [
//!   hops: [[32]u8],           // List of DIDs in chain
//!   signatures: [[64]u8],     // Sigs verifying links
//!   timestamp: u64,           // Creation time (replay protection)
//!   expires_at: u64           // Path expiration
//! ]

const std = @import("std");
const trust_graph = @import("trust_graph.zig");
const l0_transport = @import("l0_transport");
const time = l0_transport.time;
const soulkey = @import("soulkey.zig");

pub const PathVerdict = enum {
    /// Path is valid and active
    valid,
    /// Path explicitly starts/ends with wrong DIDs
    invalid_endpoints,
    /// Path expired
    expired,
    /// Path exceeds max trust depth (3 by default)
    too_deep,
    /// A link in the chain is broken (sig failure)
    broken_link,
    /// Signer revoked the trust edge
    revoked,
    /// Use for replay attacks
    replay,
};

/// Proof of Path structure
/// "I am Sender. Here is a chain of signatures proving I am trusted by you."
pub const ProofOfPath = struct {
    /// The trust chain: [Sender, Hop1, Hop2, ..., Receiver]
    hops: std.ArrayListUnmanaged([32]u8),

    /// Signatures proving each link:
    /// signatures[i] = Sig_{hops[i+1]}(hops[i] + CONTEXT)
    /// The receiver signs for Hop N-1, Hop N-1 signs for N-2...
    /// NOTE: RFC-0120 implies Trust Edges are signed credentials.
    /// Implementation: TrustEdge struct in graph is implicit proof.
    /// This struct carries the *signatures* of those TrustEdges if they are signed.
    /// For QVL v1 (local graph), PoP is a path reconstruction from local state or
    /// a transmitted bundle of Signed Trust Edges.
    ///
    /// REVISION for v1:
    /// Since we use CompactTrustGraph (local state), PoP is primarily for *exporting*
    /// a path to a receiver who *doesn't* know the sender.
    /// The signatures here must be:
    /// Link A->B: "I, B, trust A" (Signed by B)
    signatures: std.ArrayListUnmanaged([64]u8),

    /// Timestamp path was generated
    timestamp: time.SovereignTimestamp,

    /// When this proof expires (min of all edge expirations)
    expires_at: time.SovereignTimestamp,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ProofOfPath {
        return .{
            .hops = .{},
            .signatures = .{},
            .timestamp = time.SovereignTimestamp.now(), // Default, update later
            .expires_at = time.SovereignTimestamp.now().addSeconds(3600), // Default 1h
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ProofOfPath) void {
        self.hops.deinit(self.allocator);
        self.signatures.deinit(self.allocator);
    }

    /// Construct a ProofOfPath (Sender Side)
    /// Finds path in local graph and bundles it.
    /// NOTE: In v1, we assume we have the signatures or can generate them if we own the keys.
    /// Realistically, Sender constructs path from [Sender -> ... -> Receiver]
    /// But wait, Trust flows Receiver -> Sender ("Receiver trusts Sender").
    /// So the path is [Receiver -> A -> B -> Sender].
    /// Sender needs to find: "Who does Receiver trust? A. Do I know A? No. Do I know B who knows A?"
    ///
    /// RFC-0120 S4.3.3: "Sender constructs path"
    /// This implies Sender knows the Trust Graph topology.
    /// If Graph is Private, Sender *cannot* know Receiver's trustees.
    ///
    /// RESOLUTION: PoP works on *Public/Friends* edges or previously exchanged credentials.
    /// For v1 simulation: We assume Sender has a view of the graph that allows finding the path.
    pub fn construct(
        allocator: std.mem.Allocator,
        sender_did: [32]u8,
        receiver_did: [32]u8,
        graph: *const trust_graph.CompactTrustGraph,
    ) !?ProofOfPath {
        // Direction of Trust: Receiver -> ... -> Sender
        // Sender needs to prove: "Receiver trusts X, X trusts Y, Y trusts ME."
        // So we look for path: Receiver -> Sender
        const path_indices = graph.findPath(receiver_did, sender_did) orelse return null;
        defer allocator.free(path_indices);

        var pop = ProofOfPath.init(allocator); // Default timestamp/expire

        // Convert indices to DIDs
        // Path: [Receiver(IDX), Hop1(IDX), ..., Sender(IDX)]
        for (path_indices) |idx| {
            const did = graph.getDid(idx) orelse return error.NodeNotFound;
            try pop.hops.append(allocator, did);
        }

        // TODO: Retrieve specific edge signatures.
        // For v1, we mock signatures or omit if relying on local graph verification.
        // If the checking node HAS the graph (Chapter mode), it just calls verifyLocal(path).
        // If transmitting to a stranger, we need actual crypto sigs.
        // We will implement `signatures` placeholders for now.

        // Fill mock signatures for structure validity
        const sig_count = if (path_indices.len > 0) path_indices.len - 1 else 0;
        for (0..sig_count) |_| {
            var sig: [64]u8 = undefined;
            @memset(&sig, 0xEE); // Mock sig
            try pop.signatures.append(allocator, sig);
        }

        return pop;
    }

    /// Verify a received path against local Trust Graph (Receiver Side)
    /// "Did the Sender provide a valid path that I can verify locally?"
    /// Complexity: O(depth) - we just check the hops exist and link up.
    pub fn verify(
        self: *const ProofOfPath,
        expected_receiver: [32]u8,
        expected_sender: [32]u8,
        graph: *const trust_graph.CompactTrustGraph,
    ) PathVerdict {
        if (self.hops.items.len < 2) return .invalid_endpoints;

        // 1. Verify Endpoints
        // Hops[0] should be Receiver (Trust Anchor)
        // Hops[Last] should be Sender (Trust Target)
        // Direction: Receiver -> A -> B -> Sender
        if (!std.mem.eql(u8, &self.hops.items[0], &expected_receiver)) return .invalid_endpoints;
        if (!std.mem.eql(u8, &self.hops.items[self.hops.items.len - 1], &expected_sender)) return .invalid_endpoints;

        // 2. Verify Expiration
        if (self.expires_at.isBefore(time.SovereignTimestamp.now())) return .expired;

        // 3. Verify Depth
        if (self.hops.items.len - 1 > graph.config.max_trust_depth) return .too_deep;

        // 4. Verify Links (O(Depth))
        // We walk the path provided by Sender and check if our Local Graph agrees with the edges.
        // (Or verify signatures if we implemented full credential verification logic)
        var i: usize = 0;
        while (i < self.hops.items.len - 1) : (i += 1) {
            const truster_did = self.hops.items[i];
            const trustee_did = self.hops.items[i + 1];

            // Check if Truster -> Trustee exists in our view of the graph
            // Ideally, we verify the SIGNATURE here.
            // For v1 Local/Chapter verification:
            if (!graph.hasDirectTrustByDid(truster_did, trustee_did)) {
                return .broken_link;
            }
        }

        return .valid;
    }

    /// Serialize to wire byte array (simple encoding)
    pub fn serialize(self: *const ProofOfPath, allocator: std.mem.Allocator) ![]u8 {
        var list = std.ArrayListUnmanaged(u8){};
        defer list.deinit(allocator);

        const writer = list.writer(allocator);

        // Count (u8)
        try writer.writeInt(u8, @intCast(self.hops.items.len), .little);

        // Hops (32 bytes each)
        for (self.hops.items) |hop| {
            try writer.writeAll(&hop);
        }

        // Sigs (64 bytes each)
        try writer.writeInt(u8, @intCast(self.signatures.items.len), .little);
        for (self.signatures.items) |sig| {
            try writer.writeAll(&sig);
        }

        // Times (17 bytes each)
        try writer.writeAll(&self.timestamp.serialize());
        try writer.writeAll(&self.expires_at.serialize());

        return list.toOwnedSlice(allocator);
    }

    /// Deserialize from wire bytes
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !ProofOfPath {
        if (data.len < 1) return error.InvalidData;

        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();

        var pop = ProofOfPath.init(allocator);

        // Hops
        const hop_count = try reader.readInt(u8, .little);
        for (0..hop_count) |_| {
            var hop: [32]u8 = undefined;
            try reader.readNoEof(&hop);
            try pop.hops.append(allocator, hop);
        }

        // Sigs
        const sig_count = try reader.readInt(u8, .little);
        for (0..sig_count) |_| {
            var sig: [64]u8 = undefined;
            try reader.readNoEof(&sig);
            try pop.signatures.append(allocator, sig);
        }

        // Times
        var ts_buf: [17]u8 = undefined;
        try reader.readNoEof(&ts_buf);
        pop.timestamp = time.SovereignTimestamp.deserialize(&ts_buf);

        try reader.readNoEof(&ts_buf);
        pop.expires_at = time.SovereignTimestamp.deserialize(&ts_buf);

        return pop;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "ProofOfPath: construction and verification (valid flow)" {
    const allocator = std.testing.allocator;

    // 1. Setup Graph: R -> A -> S (Receiver trusts A, A trusts Sender)
    // Receiver needs to verify S is trustworthy.
    var r_did: [32]u8 = undefined;
    @memset(&r_did, 0x11); // Receiver
    var a_did: [32]u8 = undefined;
    @memset(&a_did, 0xAA); // Intermediary
    var s_did: [32]u8 = undefined;
    @memset(&s_did, 0x99); // Sender

    var graph = try trust_graph.CompactTrustGraph.init(allocator, r_did, .{});
    defer graph.deinit();

    // R trusts A
    try graph.grantTrust(a_did, .full, .friends, 0);

    // Manual edge A -> S (simulate A's trust)
    const a_idx = graph.getNode(a_did).?;
    const s_idx = try graph.getOrInsertNode(s_did);
    try graph.adjacency.items[a_idx].append(allocator, .{ .target_idx = s_idx, .level = .full, .visibility = .public, .expires_at = 0 });

    // 2. Sender constructs proof
    var pop = try ProofOfPath.construct(allocator, s_did, r_did, &graph);
    try std.testing.expect(pop != null);
    defer if (pop) |*p| p.deinit();

    // 3. Verify path contents
    try std.testing.expectEqual(@as(usize, 3), pop.?.hops.items.len); // R, A, S
    try std.testing.expectEqualSlices(u8, &r_did, &pop.?.hops.items[0]);
    try std.testing.expectEqualSlices(u8, &s_did, &pop.?.hops.items[2]);

    // 4. Receiver Validates
    const verdict = pop.?.verify(r_did, s_did, &graph);
    try std.testing.expectEqual(PathVerdict.valid, verdict);
}

test "ProofOfPath: verify broken link" {
    const allocator = std.testing.allocator;

    var r_did: [32]u8 = undefined;
    @memset(&r_did, 0x11);
    var a_did: [32]u8 = undefined;
    @memset(&a_did, 0x22);
    var s_did: [32]u8 = undefined;
    @memset(&s_did, 0x33);

    var graph = try trust_graph.CompactTrustGraph.init(allocator, r_did, .{});
    defer graph.deinit();

    // R trusts A
    try graph.grantTrust(a_did, .full, .friends, 0);
    // A doesn't trust S in the graph!

    // Create fake PoP: R->A->S
    var pop = ProofOfPath.init(allocator);
    defer pop.deinit();
    try pop.hops.append(allocator, r_did);
    try pop.hops.append(allocator, a_did);
    try pop.hops.append(allocator, s_did);

    const verdict = pop.verify(r_did, s_did, &graph);
    try std.testing.expectEqual(PathVerdict.broken_link, verdict);
}

test "ProofOfPath: serialization roundtrip" {
    const allocator = std.testing.allocator;
    var pop = ProofOfPath.init(allocator);
    defer pop.deinit();

    try pop.hops.append(allocator, [_]u8{1} ** 32);
    try pop.hops.append(allocator, [_]u8{2} ** 32);

    try pop.signatures.append(allocator, [_]u8{9} ** 64);

    const serialized = try pop.serialize(allocator);
    defer allocator.free(serialized);

    var restored = try ProofOfPath.deserialize(allocator, serialized);
    defer restored.deinit();

    try std.testing.expectEqual(pop.hops.items.len, restored.hops.items.len);
    try std.testing.expectEqualSlices(u8, &pop.hops.items[0], &restored.hops.items[0]);
    try std.testing.expectEqual(pop.signatures.items.len, restored.signatures.items.len);
}
