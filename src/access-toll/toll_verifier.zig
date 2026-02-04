// RFC-0315: Privacy-Preserving Access Tolls - Zig Verifier PoC
// Status: IMPLEMENTATION v0.1.0
// License: EUPL-1.2

const std = @import("std");
const crypto = std.crypto;
const hash = crypto.hash;

/// STARK Proof structure (placeholder - real impl uses winterfell/starky)
pub const StarkProof = struct {
    // FRI layers, constraint evaluations, etc.
    // Simplified for PoC - in production this is ~2-5KB recursive proof
    data: []const u8,
    
    pub fn deinit(self: *StarkProof, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Compressed proof for Kenya compliance (<5KB)
pub const CompressedProof = struct {
    recursive_root: [32]u8,
    compressed_data: []const u8,
    
    pub fn deinit(self: *CompressedProof, allocator: std.mem.Allocator) void {
        allocator.free(self.compressed_data);
    }
};

/// Toll band defines acceptable price range (range proof)
pub const TollBand = struct {
    min: u64,
    max: u64,
    target: u64,
    
    pub fn contains(self: TollBand, amount: u64) bool {
        return amount >= self.min and amount <= self.max;
    }
};

/// Commitment to toll payment (opaque, privacy-preserving)
pub const TollCommitment = struct {
    hash: [32]u8,  // blake3(resource_id || amount || nonce)
    
    pub fn compute(
        _allocator: std.mem.Allocator,  // Reserved for future use
        resource_id: []const u8,
        amount: u64,
        nonce: [16]u8,
    ) ![32]u8 {
        _ = _allocator;  // Explicitly ignore for now
        
        var hasher = hash.Blake3.init(.{});
        
        // Hash components
        hasher.update(resource_id);
        
        var amount_bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &amount_bytes, amount, .little);
        hasher.update(&amount_bytes);
        
        hasher.update(&nonce);
        
        var result: [32]u8 = undefined;
        hasher.final(&result);
        return result;
    }
};

/// Anti-replay nullifier
pub const Nullifier = struct {
    value: [32]u8,
    
    pub fn fromCommitment(commitment: [32]u8, secret_key: [32]u8) [32]u8 {
        var hasher = hash.Blake3.init(.{});
        hasher.update(&commitment);
        hasher.update(&secret_key);
        var result: [32]u8 = undefined;
        hasher.final(&result);
        return result;
    }
};

/// Toll clearance proof - ZK-STARK #10 from RFC-0130
pub const TollClearanceProof = struct {
    stark_proof: StarkProof,
    compressed: ?CompressedProof,  // Kenya mode
    commitment_hash: [32]u8,
    nullifier: [32]u8,  // Anti-replay
    toll_band: TollBand,
    
    pub fn deinit(self: *TollClearanceProof, allocator: std.mem.Allocator) void {
        self.stark_proof.deinit(allocator);
        if (self.compressed) |*comp| {
            comp.deinit(allocator);
        }
    }
};

/// Verification result
pub const VerificationResult = enum {
    valid,
    invalid_commitment,
    invalid_stark,
    replay_detected,
    band_violation,
};

/// Pending toll for lazy verification (Kenya mode)
pub const PendingToll = struct {
    proof: TollClearanceProof,
    received_at: i64,  // timestamp
    
    pub fn deinit(self: *PendingToll, allocator: std.mem.Allocator) void {
        self.proof.deinit(allocator);
    }
};

/// Lazy batch queue for resource-constrained routers
pub const LazyBatch = struct {
    pending: std.ArrayList(PendingToll),
    gpa: std.mem.Allocator,
    deadline: i64,
    max_size: usize,
    
    const BATCH_SIZE_DEFAULT = 100;
    const BATCH_WINDOW_MS = 5000;  // 5 seconds
    
    pub fn init(gpa: std.mem.Allocator, max_size: ?usize) LazyBatch {
        return .{
            .pending = .empty,
            .gpa = gpa,
            .deadline = std.time.milliTimestamp() + BATCH_WINDOW_MS,
            .max_size = max_size orelse BATCH_SIZE_DEFAULT,
        };
    }
    
    pub fn deinit(self: *LazyBatch) void {
        for (self.pending.items) |*item| {
            item.deinit(self.gpa);
        }
        self.pending.deinit(self.gpa);
    }
    
    /// Add proof to batch (optimistic acceptance)
    pub fn enqueue(self: *LazyBatch, proof: TollClearanceProof) !void {
        if (self.pending.items.len >= self.max_size) {
            return error.BatchFull;
        }
        
        const pending_item = PendingToll{
            .proof = proof,
            .received_at = std.time.milliTimestamp(),
        };
        
        try self.pending.append(self.gpa, pending_item);
    }
    
    /// Check if batch should flush
    pub fn shouldFlush(self: *LazyBatch) bool {
        const now = std.time.milliTimestamp();
        return now >= self.deadline or self.pending.items.len >= self.max_size;
    }
    
    /// Get pending proofs for batch verification
    pub fn flush(self: *LazyBatch) []PendingToll {
        const result = self.pending.toOwnedSlice(self.gpa) catch return &[_]PendingToll{};
        self.deadline = std.time.milliTimestamp() + BATCH_WINDOW_MS;
        return result;
    }
};

/// Nullifier cache for replay prevention
pub const NonceCache = struct {
    spent: std.AutoHashMap([32]u8, i64),
    max_age_ms: i64,
    
    pub fn init(allocator: std.mem.Allocator, max_age_ms: ?i64) NonceCache {
        return .{
            .spent = std.AutoHashMap([32]u8, i64).init(allocator),
            .max_age_ms = max_age_ms orelse (24 * 60 * 60 * 1000),  // 24h default
        };
    }
    
    pub fn deinit(self: *NonceCache) void {
        self.spent.deinit();
    }
    
    pub fn contains(self: *NonceCache, nullifier: [32]u8) bool {
        return self.spent.contains(nullifier);
    }
    
    pub fn markSpent(self: *NonceCache, nullifier: [32]u8) !void {
        const now = std.time.milliTimestamp();
        try self.spent.put(nullifier, now);
    }
    
    /// Clean old entries (call periodically)
    pub fn gc(self: *NonceCache) void {
        const now = std.time.milliTimestamp();
        var iter = self.spent.iterator();
        while (iter.next()) |entry| {
            if (now - entry.value_ptr.* > self.max_age_ms) {
                _ = self.spent.remove(entry.key_ptr.*);
            }
        }
    }
};

/// Router context for verification decisions
pub const RouterContext = struct {
    is_kenya_mode: bool,
    resource_constrained: bool,
    current_load: f32,  // 0.0 - 1.0
    
    pub fn shouldLazyVerify(self: RouterContext) bool {
        return self.is_kenya_mode or self.resource_constrained or self.current_load > 0.8;
    }
};

/// Main Toll Verifier - RFC-0315 Section 7.2
pub const TollVerifier = struct {
    allocator: std.mem.Allocator,
    nonce_cache: NonceCache,
    batch_queue: LazyBatch,
    verified_count: u64,
    rejected_count: u64,
    
    pub fn init(allocator: std.mem.Allocator) TollVerifier {
        return .{
            .allocator = allocator,
            .nonce_cache = NonceCache.init(allocator, null),
            .batch_queue = LazyBatch.init(allocator, null),
            .verified_count = 0,
            .rejected_count = 0,
        };
    }
    
    pub fn deinit(self: *TollVerifier) void {
        self.nonce_cache.deinit();
        self.batch_queue.deinit();
    }
    
    /// Verify a toll clearance proof
    /// Returns true if valid (or optimistically accepted for lazy mode)
    pub fn verifyToll(
        self: *TollVerifier,
        proof: TollClearanceProof,
        context: RouterContext,
    ) !VerificationResult {
        // 1. Check nullifier not spent (anti-replay)
        if (self.nonce_cache.contains(proof.nullifier)) {
            self.rejected_count += 1;
            return .replay_detected;
        }
        
        // 2. Verify commitment format (basic sanity check)
        if (!self.verifyCommitmentFormat(proof.commitment_hash)) {
            self.rejected_count += 1;
            return .invalid_commitment;
        }
        
        // 3. Route based on resource context
        if (context.shouldLazyVerify()) {
            // Lazy verification - accept now, verify in batch later
            try self.batch_queue.enqueue(proof);
            
            // Mark nullifier as pending (will be finalized on batch verify)
            try self.nonce_cache.markSpent(proof.nullifier);
            self.verified_count += 1;
            return .valid;
        } else {
            // Immediate verification
            const result = try self.verifyStarkImmediate(proof);
            if (result == .valid) {
                try self.nonce_cache.markSpent(proof.nullifier);
                self.verified_count += 1;
            } else {
                self.rejected_count += 1;
            }
            return result;
        }
    }
    
    /// Verify commitment hash format (not cryptographic verification)
    fn verifyCommitmentFormat(_: *TollVerifier, commitment: [32]u8) bool {
        // Non-zero check
        var all_zero = true;
        for (commitment) |b| {
            if (b != 0) {
                all_zero = false;
                break;
            }
        }
        return !all_zero;
    }
    
    /// Immediate STARK verification (production: calls winterfell/starky)
    fn verifyStarkImmediate(_: *TollVerifier, proof: TollClearanceProof) !VerificationResult {
        // PoC: Simulate verification
        // In production: verify FRI layers, constraint satisfaction, etc.
        
        // Check if proof data exists
        if (proof.stark_proof.data.len == 0) {
            return .invalid_stark;
        }
        
        // Check compressed proof if Kenya mode
        if (proof.compressed) |comp| {
            if (comp.compressed_data.len == 0) {
                return .invalid_stark;
            }
        }
        
        return .valid;
    }
    
    /// Process batch queue if ready
    pub fn processBatch(self: *TollVerifier) !void {
        if (!self.batch_queue.shouldFlush()) {
            return;
        }
        
        const pending = self.batch_queue.flush();
        defer self.allocator.free(pending);
        
        // In production: generate recursive STARK proving all pending
        // For PoC: just verify individually
        for (pending) |*item| {
            _ = try self.verifyStarkImmediate(item.proof);
            // In production: collect failures for rollback
        }
    }
    
    /// Get verification statistics
    pub fn getStats(self: *TollVerifier) struct { verified: u64, rejected: u64 } {
        return .{
            .verified = self.verified_count,
            .rejected = self.rejected_count,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "TollBand contains" {
    const band = TollBand{
        .min = 100,
        .max = 500,
        .target = 250,
    };
    
    try std.testing.expect(band.contains(100));
    try std.testing.expect(band.contains(250));
    try std.testing.expect(band.contains(500));
    try std.testing.expect(!band.contains(50));
    try std.testing.expect(!band.contains(600));
}

test "TollCommitment computation" {
    const allocator = std.testing.allocator;
    
    const resource_id = "test-resource-123";
    const amount: u64 = 250;
    const nonce = [_]u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16};
    
    const commitment = try TollCommitment.compute(allocator, resource_id, amount, nonce);
    
    // Verify deterministic
    const commitment2 = try TollCommitment.compute(allocator, resource_id, amount, nonce);
    try std.testing.expectEqual(commitment, commitment2);
    
    // Different inputs = different outputs
    const commitment3 = try TollCommitment.compute(allocator, resource_id, amount + 1, nonce);
    var all_same = true;
    for (commitment, commitment3) |a, b| {
        if (a != b) {
            all_same = false;
            break;
        }
    }
    try std.testing.expect(!all_same);
}

test "NonceCache replay prevention" {
    const allocator = std.testing.allocator;
    var cache = NonceCache.init(allocator, null);
    defer cache.deinit();
    
    const nullifier = [_]u8{1} ** 32;
    
    try std.testing.expect(!cache.contains(nullifier));
    try cache.markSpent(nullifier);
    try std.testing.expect(cache.contains(nullifier));
}

test "TollVerifier immediate verify" {
    const allocator = std.testing.allocator;
    var verifier = TollVerifier.init(allocator);
    defer verifier.deinit();
    
    // Create a valid proof
    const proof = TollClearanceProof{
        .stark_proof = .{ .data = "valid-proof-data" },
        .compressed = null,
        .commitment_hash = [_]u8{1} ** 32,
        .nullifier = [_]u8{2} ** 32,
        .toll_band = .{ .min = 100, .max = 500, .target = 250 },
    };
    
    const context = RouterContext{
        .is_kenya_mode = false,
        .resource_constrained = false,
        .current_load = 0.5,
    };
    
    const result = try verifier.verifyToll(proof, context);
    try std.testing.expectEqual(result, .valid);
    
    // Verify replay detection
    const result2 = try verifier.verifyToll(proof, context);
    try std.testing.expectEqual(result2, .replay_detected);
}

test "TollVerifier lazy batch mode" {
    const allocator = std.testing.allocator;
    var verifier = TollVerifier.init(allocator);
    defer verifier.deinit();
    
    const context = RouterContext{
        .is_kenya_mode = true,  // Enable lazy mode
        .resource_constrained = false,
        .current_load = 0.5,
    };
    
    // Enqueue multiple proofs
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const proof = TollClearanceProof{
            .stark_proof = .{ .data = try allocator.dupe(u8, "proof-data") },
            .compressed = null,
            .commitment_hash = [_]u8{@intCast(i + 1)} ** 32,
            .nullifier = [_]u8{@intCast(i + 10)} ** 32,
            .toll_band = .{ .min = 100, .max = 500, .target = 250 },
        };
        
        const result = try verifier.verifyToll(proof, context);
        try std.testing.expectEqual(result, .valid);
    }
    
    // Check batch queue has items
    try std.testing.expect(verifier.batch_queue.pending.items.len > 0);
    
    // Process batch
    try verifier.processBatch();
    
    // Check stats
    const stats = verifier.getStats();
    try std.testing.expectEqual(stats.verified, 5);
}

test "Nullifier generation" {
    const commitment = [_]u8{1, 2, 3} ++ [_]u8{0} ** 29;
    const secret_key = [_]u8{4, 5, 6} ++ [_]u8{0} ** 29;
    
    const nullifier = Nullifier.fromCommitment(commitment, secret_key);
    const nullifier2 = Nullifier.fromCommitment(commitment, secret_key);
    
    // Deterministic
    try std.testing.expectEqual(nullifier, nullifier2);
    
    // Different inputs = different outputs
    const different_key = [_]u8{7, 8, 9} ++ [_]u8{0} ** 29;
    const nullifier3 = Nullifier.fromCommitment(commitment, different_key);
    var all_same = true;
    for (nullifier, nullifier3) |a, b| {
        if (a != b) {
            all_same = false;
            break;
        }
    }
    try std.testing.expect(!all_same);
}

// Demo/example usage
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== RFC-0315 Toll Verifier PoC ===\n\n", .{});
    
    // Initialize verifier
    var verifier = TollVerifier.init(allocator);
    defer verifier.deinit();
    
    std.debug.print("[1] Verifier initialized\n", .{});
    
    // Create a toll commitment
    const resource_id = "premium-feed-access";
    const amount: u64 = 250;
    const nonce = [_]u8{0xAB} ** 16;
    
    const commitment = try TollCommitment.compute(allocator, resource_id, amount, nonce);
    std.debug.print("[2] Commitment computed: ", .{});
    for (commitment) |b| {
        std.debug.print("{x:0>2}", .{b});
    }
    std.debug.print("\n", .{});
    
    // Create proof (in production: generated via ZK-STARK)
    const proof = TollClearanceProof{
        .stark_proof = .{ .data = "stark-proof-placeholder" },
        .compressed = null,
        .commitment_hash = commitment,
        .nullifier = Nullifier.fromCommitment(commitment, [_]u8{0xCD} ** 32),
        .toll_band = .{ .min = 100, .max = 500, .target = 250 },
    };
    
    // Verify in normal mode
    const normal_context = RouterContext{
        .is_kenya_mode = false,
        .resource_constrained = false,
        .current_load = 0.5,
    };
    
    const result = try verifier.verifyToll(proof, normal_context);
    std.debug.print("[3] Immediate verification: {s}\n", .{@tagName(result)});
    
    // Demonstrate Kenya mode (lazy batching)
    std.debug.print("\n[4] Kenya Mode (lazy batching):\n", .{});
    
    const kenya_context = RouterContext{
        .is_kenya_mode = true,
        .resource_constrained = true,
        .current_load = 0.9,
    };
    
    // Simulate 10 tolls
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const k_commitment = try TollCommitment.compute(
            allocator, 
            resource_id, 
            amount + @as(u64, @intCast(i)),  // Varying amounts
            [_]u8{@intCast(i)} ** 16,
        );
        
        const k_proof = TollClearanceProof{
            .stark_proof = .{ .data = try allocator.dupe(u8, "kenya-proof") },
            .compressed = .{
                .recursive_root = [_]u8{0xFF} ** 32,
                .compressed_data = try allocator.dupe(u8, "compressed"),
            },
            .commitment_hash = k_commitment,
            .nullifier = Nullifier.fromCommitment(k_commitment, [_]u8{@intCast(i)} ** 32),
            .toll_band = .{ .min = 100, .max = 600, .target = 300 },
        };
        
        const k_result = try verifier.verifyToll(k_proof, kenya_context);
        std.debug.print("    Toll {d}: {s} (queued)\n", .{ i + 1, @tagName(k_result) });
    }
    
    // Process batch
    try verifier.processBatch();
    std.debug.print("[5] Batch processed\n", .{});
    
    // Final stats
    const stats = verifier.getStats();
    std.debug.print("\n[Stats] Verified: {d}, Rejected: {d}\n", .{ 
        stats.verified, 
        stats.rejected 
    });
    
    std.debug.print("\n=== RFC-0315 PoC Complete ===\n", .{});
}
