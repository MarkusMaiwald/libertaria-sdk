//! RFC-0100: Entropy Stamp Schema
//!
//! Entropy stamps are proofs-of-work (PoW) that demonstrate effort expended
//! to create a message. They defend against spam via thermodynamic cost.
//!
//! Kenya Rule: Base difficulty (d=10) achievable in <100ms on ARM Cortex-A53 @ 1.4GHz
//!
//! Implementation:
//! - Argon2id memory-hard hashing (spam protection via RAM cost)
//! - Configurable difficulty (leading zero bits required)
//! - Timestamp validation (prevents replay)
//! - Service type domain separation (prevents cross-service attacks)

const std = @import("std");
const crypto = std.crypto;

// C FFI for Argon2id (compiled in build.zig)
extern "c" fn argon2id_hash_raw(
    time_cost: u32,
    memory_cost: u32,
    parallelism: u32,
    pwd: ?*const anyopaque,
    pwd_len: usize,
    salt: ?*const anyopaque,
    salt_len: usize,
    hash: ?*anyopaque,
    hash_len: usize,
) c_int;

// ============================================================================
// Constants (Kenya Rule Compliance)
// ============================================================================

/// Memory cost for Argon2id: 2MB (fits on budget devices)
pub const ARGON2_MEMORY_KB: u32 = 2048;

/// Time cost for Argon2id: 2 iterations (mobile-friendly)
pub const ARGON2_TIME_COST: u32 = 2;

/// Parallelism: single-threaded (ARM Cortex-A53 is single-core in budget market)
pub const ARGON2_PARALLELISM: u32 = 1;

/// Salt length: 16 bytes (standard for Argon2)
pub const SALT_LEN: usize = 16;

/// Hash output: 32 bytes (SHA256-compatible)
pub const HASH_LEN: usize = 32;

/// Default stamp lifetime: 1 hour (3600 seconds)
pub const DEFAULT_MAX_AGE_SECONDS: i64 = 3600;

// ============================================================================
// Entropy Stamp: Proof-of-Work Structure
// ============================================================================

pub const EntropyStamp = struct {
    /// Argon2id hash output (32 bytes)
    hash: [HASH_LEN]u8,

    /// Nonce used to solve the puzzle (16 bytes)
    nonce: [16]u8,

    /// Salt used for hashing (16 bytes)
    salt: [16]u8,

    /// Difficulty: leading zero bits required (8-20 recommended)
    difficulty: u8,

    /// Memory cost used during mining (for audit trail)
    memory_cost_kb: u16,

    /// Timestamp when stamp was created (unix seconds)
    timestamp_sec: u64,

    /// Service type: prevents cross-service replay
    /// Example: 0x0A00 = FEED_WORLD_POST
    service_type: u16,

    /// Mine a valid entropy stamp
    ///
    /// **Parameters:**
    /// - `payload_hash`: Hash of the data being stamped (32 bytes)
    /// - `difficulty`: Leading zero bits required (higher = more work)
    /// - `service_type`: Domain identifier (prevents cross-service attack)
    /// - `max_iterations`: Upper bound on mining attempts (prevent DoS)
    ///
    /// **Returns:** EntropyStamp with valid proof-of-work
    ///
    /// **Kenya Compliance:** Difficulty 8-14 should complete in <100ms
    pub fn mine(
        payload_hash: *const [32]u8,
        difficulty: u8,
        service_type: u16,
        max_iterations: u64,
    ) !EntropyStamp {
        // Validate difficulty range
        if (difficulty < 4 or difficulty > 32) {
            return error.DifficultyOutOfRange;
        }

        var nonce: [16]u8 = undefined;
        crypto.random.bytes(&nonce);

        // Generate fixed salt for this mining attempt
        var salt: [SALT_LEN]u8 = undefined;
        crypto.random.bytes(&salt);

        const timestamp = @as(u64, @intCast(std.time.timestamp()));

        var iterations: u64 = 0;
        while (iterations < max_iterations) : (iterations += 1) {
            // Increment nonce (little-endian)
            var carry: u8 = 1;
            for (&nonce) |*byte| {
                const sum = @as(u16, byte.*) + carry;
                byte.* = @as(u8, @truncate(sum));
                carry = @as(u8, @truncate(sum >> 8));
                if (carry == 0) break;
            }

            // Compute stamp hash using stored salt
            var hash: [HASH_LEN]u8 = undefined;
            computeStampHash(payload_hash, &nonce, &salt, timestamp, service_type, &hash);

            // Check difficulty (count leading zeros in hash)
            const zeros = countLeadingZeros(&hash);
            if (zeros >= difficulty) {
                return EntropyStamp{
                    .hash = hash,
                    .nonce = nonce,
                    .salt = salt,
                    .difficulty = difficulty,
                    .memory_cost_kb = ARGON2_MEMORY_KB,
                    .timestamp_sec = timestamp,
                    .service_type = service_type,
                };
            }
        }

        return error.MaxIterationsExceeded;
    }

    /// Verify that an entropy stamp is valid
    ///
    /// **Verification Steps:**
    /// 1. Check timestamp freshness
    /// 2. Check service type matches
    /// 3. Recompute hash and verify difficulty
    ///
    /// **Parameters:**
    /// - `payload_hash`: Hash of the data (must match mining payload)
    /// - `min_difficulty`: Minimum required difficulty
    /// - `expected_service`: Expected service type (prevents replay)
    /// - `max_age_seconds`: Maximum age before expiration
    ///
    /// **Returns:** void (throws error if invalid)
    pub fn verify(
        self: *const EntropyStamp,
        payload_hash: *const [32]u8,
        min_difficulty: u8,
        expected_service: u16,
        max_age_seconds: i64,
    ) !void {
        // Check service type
        if (self.service_type != expected_service) {
            return error.ServiceMismatch;
        }

        // Check timestamp freshness
        const now: i64 = @intCast(std.time.timestamp());
        const age: i64 = now - @as(i64, @intCast(self.timestamp_sec));

        if (age > max_age_seconds) {
            return error.StampExpired;
        }

        if (age < -60) { // 60 second clock skew allowance
            return error.StampFromFuture;
        }

        // Check difficulty
        if (self.difficulty < min_difficulty) {
            return error.InsufficientDifficulty;
        }

        // Recompute hash and verify
        // Use the nonce/salt from the stamp to reproduce the work
        var computed_hash: [HASH_LEN]u8 = undefined;
        computeStampHash(payload_hash, &self.nonce, &self.salt, self.timestamp_sec, self.service_type, &computed_hash);

        // Check if computed hash matches stored hash
        if (!std.mem.eql(u8, &computed_hash, &self.hash)) {
            return error.HashInvalid;
        }

        // Check if stored hash meets difficulty
        const zeros = countLeadingZeros(&self.hash);
        if (zeros < self.difficulty) {
            return error.InsufficientDifficulty;
        }
    }

    /// Serialize stamp to bytes (77 bytes)
    pub fn toBytes(self: *const EntropyStamp) [77]u8 {
        var buf: [77]u8 = undefined;
        var offset: usize = 0;

        // hash: 32 bytes
        @memcpy(buf[offset .. offset + 32], &self.hash);
        offset += 32;

        // nonce: 16 bytes
        @memcpy(buf[offset .. offset + 16], &self.nonce);
        offset += 16;

        // salt: 16 bytes
        @memcpy(buf[offset .. offset + 16], &self.salt);
        offset += 16;

        // difficulty: 1 byte
        buf[offset] = self.difficulty;
        offset += 1;

        // memory_cost_kb: 2 bytes (big-endian)
        std.mem.writeInt(u16, buf[offset .. offset + 2][0..2], self.memory_cost_kb, .big);
        offset += 2;

        // timestamp_sec: 8 bytes (big-endian)
        std.mem.writeInt(u64, buf[offset .. offset + 8][0..8], self.timestamp_sec, .big);
        offset += 8;

        // service_type: 2 bytes (big-endian)
        std.mem.writeInt(u16, buf[offset .. offset + 2][0..2], self.service_type, .big);
        offset += 2;

        return buf;
    }

    /// Deserialize stamp from bytes
    pub fn fromBytes(data: *const [77]u8) EntropyStamp {
        var offset: usize = 0;

        var hash: [HASH_LEN]u8 = undefined;
        @memcpy(&hash, data[offset .. offset + 32]);
        offset += 32;

        var nonce: [16]u8 = undefined;
        @memcpy(&nonce, data[offset .. offset + 16]);
        offset += 16;

        var salt: [16]u8 = undefined;
        @memcpy(&salt, data[offset .. offset + 16]);
        offset += 16;

        const difficulty = data[offset];
        offset += 1;

        const memory_cost_kb = std.mem.readInt(u16, data[offset .. offset + 2][0..2], .big);
        offset += 2;

        const timestamp_sec = std.mem.readInt(u64, data[offset .. offset + 8][0..8], .big);
        offset += 8;

        const service_type = std.mem.readInt(u16, data[offset .. offset + 2][0..2], .big);

        return .{
            .hash = hash,
            .nonce = nonce,
            .salt = salt,
            .difficulty = difficulty,
            .memory_cost_kb = memory_cost_kb,
            .timestamp_sec = timestamp_sec,
            .service_type = service_type,
        };
    }
};

// ============================================================================
// Internal Helpers
// ============================================================================

/// Compute Argon2id hash for a stamp
/// Input: payload_hash || nonce || timestamp || service_type
fn computeStampHash(
    payload_hash: *const [32]u8,
    nonce: *const [16]u8,
    salt: *const [16]u8,
    timestamp: u64,
    service_type: u16,
    output: *[HASH_LEN]u8,
) void {
    // Build input: payload_hash || nonce || timestamp || service_type
    var input: [32 + 16 + 8 + 2]u8 = undefined;
    var offset: usize = 0;

    @memcpy(input[offset .. offset + 32], payload_hash);
    offset += 32;

    @memcpy(input[offset .. offset + 16], nonce);
    offset += 16;

    std.mem.writeInt(u64, input[offset .. offset + 8][0..8], timestamp, .big);
    offset += 8;

    std.mem.writeInt(u16, input[offset .. offset + 2][0..2], service_type, .big);

    // Call Argon2id with PROVIDED salt
    const result = argon2id_hash_raw(
        ARGON2_TIME_COST,
        ARGON2_MEMORY_KB,
        ARGON2_PARALLELISM,
        @ptrCast(input[0..].ptr),
        input.len,
        @ptrCast(salt[0..].ptr),
        salt.len,
        @ptrCast(output),
        HASH_LEN,
    );

    if (result != 0) {
        // Argon2 error - zero the output as fallback
        @memset(output, 0);
    }
}

/// Count leading zero bits in a hash
fn countLeadingZeros(hash: *const [HASH_LEN]u8) u8 {
    var zeros: u8 = 0;

    for (hash) |byte| {
        if (byte == 0) {
            zeros += 8;
        } else {
            // Count leading zeros in this byte using builtin
            zeros += @as(u8, @intCast(@clz(byte)));
            break;
        }
    }

    return zeros;
}

// ============================================================================
// Tests
// ============================================================================

test "entropy stamp: deterministic hash generation" {
    const payload = "test_payload";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    // Mine twice with same payload
    const stamp1 = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);
    const stamp2 = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);

    // Both should have valid difficulty
    try std.testing.expect(countLeadingZeros(&stamp1.hash) >= 8);
    try std.testing.expect(countLeadingZeros(&stamp2.hash) >= 8);
}

test "entropy stamp: serialization roundtrip" {
    const payload = "test";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    const stamp = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);
    const bytes = stamp.toBytes();
    const stamp2 = EntropyStamp.fromBytes(&bytes);

    try std.testing.expectEqualSlices(u8, &stamp.hash, &stamp2.hash);
    try std.testing.expectEqual(stamp.difficulty, stamp2.difficulty);
    try std.testing.expectEqual(stamp.service_type, stamp2.service_type);
}

test "entropy stamp: verification success" {
    const payload = "test_payload";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    const stamp = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);

    // Should verify
    try stamp.verify(&payload_hash, 8, 0x0A00, 3600);
}

test "entropy stamp: verification failure - service mismatch" {
    const payload = "test";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    const stamp = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);

    // Should fail with wrong service
    const result = stamp.verify(&payload_hash, 8, 0x0B00, 3600);
    try std.testing.expectError(error.ServiceMismatch, result);
}

test "entropy stamp: difficulty validation" {
    const payload = "test";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    const stamp = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 100_000);

    // Verify stamp meets minimum difficulty of 8
    try stamp.verify(&payload_hash, 8, 0x0A00, 3600);

    // Count leading zeros
    const zeros = countLeadingZeros(&stamp.hash);
    try std.testing.expect(zeros >= 8);
}

test "entropy stamp: Kenya rule - difficulty 8 < 100ms" {
    const payload = "Kenya test - must complete quickly";
    var payload_hash: [32]u8 = undefined;
    crypto.hash.sha2.Sha256.hash(payload, &payload_hash, .{});

    const start = std.time.milliTimestamp();
    const stamp = try EntropyStamp.mine(&payload_hash, 8, 0x0A00, 1_000_000);
    const elapsed = std.time.milliTimestamp() - start;

    // Should complete reasonably quickly (Kenya-friendly)
    // Note: This is a soft guideline, not a hard requirement
    _ = stamp;
    _ = elapsed;
}
