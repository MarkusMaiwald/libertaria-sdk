//! Quasar Vector (RFC-0120)
//!
//! The atomic unit of communication in QVL. Replaces "transactions".
//! vectors are Events.
//!
//! Structure:
//! - Source DID (32 bytes)
//! - Target DID (32 bytes)
//! - Vector Type (2 bytes)
//! - Payload Hash (32 bytes)
//! - Payload (Optional)
//! - Signature (64 bytes) -- covers above fields
//! - Trust Path (ProofOfPath) -- hardening
//! - Entropy Proof (EntropyStamp) -- anti-spam
//! - Timestamp (SovereignTimestamp)
//! - Graphology (Meta)
//! - Nonce (8 bytes)

const std = @import("std");
const time = @import("time");
const proof_of_path = @import("proof_of_path.zig");
const soulkey = @import("soulkey");
const entropy = @import("entropy.zig");
const trust_graph = @import("trust_graph");

/// Vector Type (RFC-0120 S4.2)
pub const VectorType = enum(u16) {
    // Communication (0x0700-0x070F)
    message = 0x0700,
    message_ack = 0x0701,

    // Value Transfer (0x0710-0x071F) - triggers L2
    value_transfer = 0x0710,
    value_receipt = 0x0711,

    // Credentials (0x0720-0x072F)
    credential_issue = 0x0720,
    credential_revoke = 0x0721,

    // Trust Graph (0x0730-0x073F)
    trust_grant = 0x0730,
    trust_revoke = 0x0731,
    trust_delegate = 0x0732,

    // Anchoring (0x0740-0x074F)
    anchor_commit = 0x0740,
    anchor_proof = 0x0741,

    // Explorer (0x0750-0x075F)
    explorer_probe = 0x0750,
    explorer_signal = 0x0751,
};

/// Graphology Metadata (8 bytes)
/// Measures the "shape" of the relationship
pub const GraphologyMeta = packed struct {
    trust_depth: u8, // 0 = direct, 255 = void
    mutual_contacts: u8, // Shared nodes (capped at 255)
    path_reputation: u16, // 0-65535 scaled to 0.0-1.0
    flags: GraphologyFlags, // Bit flags (4 bytes padding/flags)
};

pub const GraphologyFlags = packed struct {
    first_contact: bool,
    whitelisted: bool,
    blacklisted: bool,
    from_void: bool,
    degraded_path: bool,
    _pad: u27,
};

/// The Quasar Vector
pub const QuasarVector = struct {
    // === Identity (64 bytes) ===
    source_did: [32]u8,
    target_did: [32]u8, // 0x00 for broadcast

    // === Type (2 bytes) ===
    vector_type: VectorType,

    // === Payload ===
    payload_hash: [32]u8,
    payload: ?[]u8, // Optional content

    // === Authentication ===
    signature: [64]u8, // Ed25519 over body
    trust_path: ?proof_of_path.ProofOfPath, // Optional for direct peers
    entropy_stamps: std.ArrayListUnmanaged(entropy.EntropyStamp), // PoW

    // === Metadata ===
    created_at: time.SovereignTimestamp, // Creation time
    graphology: GraphologyMeta,
    nonce: u64, // Replay protection

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) QuasarVector {
        return .{
            .source_did = [_]u8{0} ** 32,
            .target_did = [_]u8{0} ** 32,
            .vector_type = .message,
            .payload_hash = [_]u8{0} ** 32,
            .payload = null,
            .signature = [_]u8{0} ** 64,
            .trust_path = null,
            .entropy_stamps = .{},
            .created_at = time.SovereignTimestamp.now(),
            .graphology = std.mem.zeroes(GraphologyMeta),
            .nonce = std.crypto.random.int(u64), // Secure random nonce
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *QuasarVector) void {
        if (self.payload) |p| self.allocator.free(p);
        if (self.trust_path) |*tp| tp.deinit();
        self.entropy_stamps.deinit(self.allocator);
    }

    /// Sign the vector (Ed25519)
    /// Signs: source || target || type || hash || created_at || nonce
    pub fn sign(self: *QuasarVector, sk: *const soulkey.SoulKey) !void {
        var msg = std.ArrayListUnmanaged(u8){};
        defer msg.deinit(self.allocator);
        const writer = msg.writer(self.allocator);

        try writer.writeAll(&self.source_did);
        try writer.writeAll(&self.target_did);
        try writer.writeInt(u16, @intFromEnum(self.vector_type), .little);
        try writer.writeAll(&self.payload_hash);
        try writer.writeAll(&self.created_at.serialize());
        try writer.writeInt(u64, self.nonce, .little);

        const sig = try sk.sign(msg.items);
        self.signature = sig;
    }

    /// Verify signature
    pub fn verifySignature(self: *const QuasarVector) bool {
        var msg = std.ArrayListUnmanaged(u8){};
        defer msg.deinit(self.allocator);
        const writer = msg.writer(self.allocator);

        writer.writeAll(&self.source_did) catch return false;
        writer.writeAll(&self.target_did) catch return false;
        writer.writeInt(u16, @intFromEnum(self.vector_type), .little) catch return false;
        writer.writeAll(&self.payload_hash) catch return false;
        writer.writeAll(&self.created_at.serialize()) catch return false;
        writer.writeInt(u64, self.nonce, .little) catch return false;

        return soulkey.SoulKey.verify(self.source_did, msg.items, self.signature) catch false;
    }

    /// Full Validation Pipeline (Reality Tunnel Hook)
    /// Checks: Signature, Time, Trust Path
    pub fn validate(
        self: *const QuasarVector,
        graph: *const trust_graph.CompactTrustGraph,
    ) ValidationResult {
        // 1. Signature Check
        if (!self.verifySignature()) return .invalid_signature;

        // 2. Time Check
        const now = time.SovereignTimestamp.now();
        switch (self.created_at.validateForVector(now)) {
            .valid => {},
            .too_far_future => return .future_timestamp,
            .too_old => return .expired,
        }

        // 3. Trust Check
        // If ProofOfPath provided, verify it
        if (self.trust_path) |*pop| {
            const verdict = pop.verify(self.target_did, self.source_did, graph);
            if (verdict != .valid) return .invalid_trust_path;
        } else {
            // No proof provided - check direct trust
            if (!graph.hasDirectTrustByDid(self.target_did, self.source_did)) {
                return .unknown_sender; // Airlock rejection
            }
        }

        return .valid;
    }

    pub const ValidationResult = enum {
        valid,
        invalid_signature,
        future_timestamp,
        expired,
        invalid_trust_path,
        unknown_sender,
    };

    /// Set Payload
    pub fn setPayload(self: *QuasarVector, data: []const u8) !void {
        if (self.payload) |p| self.allocator.free(p);
        self.payload = try self.allocator.dupe(u8, data);
        std.crypto.hash.Blake3.hash(data, &self.payload_hash, .{});
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "QuasarVector: init and sign" {
    const allocator = std.testing.allocator;

    // Create a keypair
    var sk = try soulkey.SoulKey.generate();

    var vector = QuasarVector.init(allocator);
    defer vector.deinit();

    vector.source_did = sk.ed25519_public;
    try vector.setPayload("Hello QVL!");

    // Sign
    try vector.sign(&sk);

    // Verify
    try std.testing.expect(vector.verifySignature());

    // Tamper
    vector.nonce += 1;
    try std.testing.expect(!vector.verifySignature());
}

test "QuasarVector: validation flow" {
    const allocator = std.testing.allocator;

    // Setup: Receiver trusts A. A trusts Sender.
    // Sender sends vector to Receiver with ProofOfPath(R->A->S).

    // 1. Keys
    const k_r = try soulkey.SoulKey.generate(); // Receiver
    const k_a = try soulkey.SoulKey.generate(); // Intermediary
    var k_s = try soulkey.SoulKey.generate(); // Sender

    // 2. Receiver's Trust Graph
    var graph = try trust_graph.CompactTrustGraph.init(allocator, k_r.ed25519_public, .{});
    defer graph.deinit();
    try graph.grantTrust(k_a.ed25519_public, .full, .friends, 0);

    // Manual edge in graph for path finding (A->S)
    const a_idx = graph.getNode(k_a.ed25519_public).?;
    const s_idx = try graph.getOrInsertNode(k_s.ed25519_public);
    try graph.adjacency.items[a_idx].append(allocator, .{ .target_idx = s_idx, .level = .full, .visibility = .public, .expires_at = 0 });

    // 3. Sender creates Vector
    var vector = QuasarVector.init(allocator);
    defer vector.deinit();
    vector.source_did = k_s.ed25519_public;
    vector.target_did = k_r.ed25519_public;
    try vector.sign(&k_s);

    // 4. Validation (Should fail: unknown sender, no proof)
    try std.testing.expectEqual(QuasarVector.ValidationResult.unknown_sender, vector.validate(&graph));

    // 5. Add Proof
    const pop = try proof_of_path.ProofOfPath.construct(allocator, k_s.ed25519_public, k_r.ed25519_public, &graph);
    vector.trust_path = pop;

    // 6. Validation (Should pass)
    try std.testing.expectEqual(QuasarVector.ValidationResult.valid, vector.validate(&graph));
}
