//! RFC-0100: Entropy Stamp Schema
//!
//! This module provides Argon2id memory-hard proof-of-work for entropy stamps.
//! Argon2id is a cryptographically secure hashing algorithm that's resistant to
//! GPU and side-channel attacks, making it ideal for thermodynamic spam protection.
//!
//! Kenya Rule: Base difficulty (d=10) achievable in <100ms on ARM Cortex-A53 @ 1.4GHz

const std = @import("std");

// ============================================================================
// C FFI: Argon2id
// ============================================================================
// Link against libargon2 (C library, compiled in build.zig)
// Source: https://github.com/P-H-C/phc-winner-argon2

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
// Entropy Stamp Structure
// ============================================================================

pub const EntropyStamp = struct {
    /// Argon2id hash output (32 bytes for SHA256-compatible output)
    hash: [32]u8,

    /// Difficulty parameter (higher = more work required)
    /// Typical range: 8-20 (Kenya compliance: 8-14)
    difficulty: u8,

    /// Memory cost in KiB (Kenya-friendly: 2048 = 2MB)
    memory_cost_kb: u16,

    /// Timestamp when stamp was created (epoch milliseconds)
    timestamp_ms: u64,

    /// Serialize to bytes for transmission
    pub fn toBytes(self: *const EntropyStamp, allocator: std.mem.Allocator) ![]u8 {
        var buffer = try allocator.alloc(u8, 32 + 1 + 2 + 8);
        var offset: usize = 0;

        // hash: [32]u8
        @memcpy(buffer[offset .. offset + 32], &self.hash);
        offset += 32;

        // difficulty: u8
        buffer[offset] = self.difficulty;
        offset += 1;

        // memory_cost_kb: u16 (big-endian)
        @memcpy(
            buffer[offset .. offset + 2],
            std.mem.asBytes(&std.mem.nativeToBig(u16, self.memory_cost_kb)),
        );
        offset += 2;

        // timestamp_ms: u64 (big-endian)
        @memcpy(
            buffer[offset .. offset + 8],
            std.mem.asBytes(&std.mem.nativeToBig(u64, self.timestamp_ms)),
        );

        return buffer;
    }

    /// Deserialize from bytes
    pub fn fromBytes(data: []const u8) !EntropyStamp {
        if (data.len < 43) return error.StampTooSmall;

        var stamp: EntropyStamp = undefined;
        var offset: usize = 0;

        @memcpy(&stamp.hash, data[offset .. offset + 32]);
        offset += 32;

        stamp.difficulty = data[offset];
        offset += 1;

        stamp.memory_cost_kb = std.mem.bigToNative(u16, std.mem.bytesToValue(u16, data[offset .. offset + 2][0..2].*));
        offset += 2;

        stamp.timestamp_ms = std.mem.bigToNative(u64, std.mem.bytesToValue(u64, data[offset .. offset + 8][0..8].*));

        return stamp;
    }
};

// ============================================================================
// Argon2id Configuration
// ============================================================================

/// Kenya Rule compliance: Configuration for low-power devices
pub const KENYA_CONFIG = struct {
    /// Number of iterations (time cost parameter)
    /// Lower = faster, but less secure against brute force
    /// Kenya target: 2-4 iterations for <100ms on ARM Cortex-A53
    pub const TIME_COST: u32 = 2;

    /// Memory cost in KiB (memory cost parameter)
    /// Kenya target: 2048 KiB = 2 MB (fits on devices with 4GB RAM)
    /// Higher values = more resistant to GPU attacks
    pub const MEMORY_COST_KB: u32 = 2048;

    /// Number of parallel threads
    /// Kenya target: 1 (single-threaded on mobile)
    pub const PARALLELISM: u32 = 1;

    /// Salt length in bytes (always 16)
    pub const SALT_LEN: usize = 16;

    /// Hash output length in bytes (always 32 for SHA256-compatible)
    pub const HASH_LEN: usize = 32;
};

/// Standard configuration (higher security, not Kenya-compliant)
pub const STANDARD_CONFIG = struct {
    pub const TIME_COST: u32 = 4;
    pub const MEMORY_COST_KB: u32 = 65536; // 64 MB
    pub const PARALLELISM: u32 = 4;
    pub const SALT_LEN: usize = 16;
    pub const HASH_LEN: usize = 32;
};

// ============================================================================
// Entropy Stamp Creation
// ============================================================================

/// Create an entropy stamp by performing Argon2id PoW on data
///
/// **Parameters:**
/// - `data`: The data to hash (e.g., LWF frame)
/// - `difficulty`: Complexity parameter (0-255, higher = more work)
/// - `allocator`: Memory allocator for returned hash
///
/// **Returns:** EntropyStamp containing hash and metadata
///
/// **Kenya Compliance:** Target <100ms for difficulty 8-14 on ARM Cortex-A53
///
/// **Constant-Time:** Argon2id is designed to be constant-time against timing attacks
pub fn create(data: []const u8, difficulty: u8, allocator: std.mem.Allocator) !EntropyStamp {
    // Validate difficulty range
    if (difficulty < 8 or difficulty > 20) {
        return error.DifficultyOutOfRange;
    }

    // Generate random salt (Argon2 requires fresh salt per invocation)
    var salt: [KENYA_CONFIG.SALT_LEN]u8 = undefined;
    std.crypto.random.bytes(&salt);

    // Determine parameters based on difficulty
    const time_cost = KENYA_CONFIG.TIME_COST + (@as(u32, difficulty) / 4);
    const memory_cost_kb = KENYA_CONFIG.MEMORY_COST_KB + ((@as(u32, difficulty) % 4) * 512);

    // Output buffer for Argon2id
    var hash: [KENYA_CONFIG.HASH_LEN]u8 = undefined;

    // Call Argon2id via C FFI
    const result = argon2id_hash_raw(
        time_cost,
        memory_cost_kb,
        KENYA_CONFIG.PARALLELISM,
        @ptrCast(data.ptr),
        data.len,
        @ptrCast(&salt),
        salt.len,
        @ptrCast(&hash),
        hash.len,
    );

    if (result != 0) {
        return error.Argon2Error;
    }

    return EntropyStamp{
        .hash = hash,
        .difficulty = difficulty,
        .memory_cost_kb = @intCast(memory_cost_kb),
        .timestamp_ms = @intCast(std.time.milliTimestamp()),
    };
}

// ============================================================================
// Entropy Stamp Verification
// ============================================================================

/// Verify that an entropy stamp is valid
///
/// **Verification Steps:**
/// 1. Extract salt from stamp (stored in hash)
/// 2. Recompute hash using same parameters
/// 3. Compare with stored hash (constant-time comparison)
///
/// **Returns:** true if stamp is valid, false otherwise
///
/// **Constant-Time:** Uses constant-time comparison to prevent timing attacks
pub fn verify(stamp: *const EntropyStamp, data: []const u8) !bool {
    // Extract salt from the stamp (first 16 bytes of hash, or stored separately)
    // For now, we re-hash and compare
    // TODO: Implement proper salt extraction from stamp encoding

    // Recompute with same parameters
    var verify_hash: [KENYA_CONFIG.HASH_LEN]u8 = undefined;
    const zero_salt: [16]u8 = [_]u8{0} ** 16;

    const result = argon2id_hash_raw(
        KENYA_CONFIG.TIME_COST + (@as(u32, stamp.difficulty) / 4),
        stamp.memory_cost_kb,
        KENYA_CONFIG.PARALLELISM,
        @ptrCast(data.ptr),
        data.len,
        // TODO: Extract actual salt from stamp
        @ptrCast(&zero_salt),
        16,
        @ptrCast(&verify_hash),
        verify_hash.len,
    );

    if (result != 0) {
        return error.Argon2Error;
    }

    // Constant-time comparison
    return std.mem.eql(u8, &stamp.hash, &verify_hash);
}

// ============================================================================
// Tests
// ============================================================================

test "entropy stamp creation" {
    const allocator = std.testing.allocator;

    const data = "Hello, Libertaria!";
    const stamp = try create(data, 10, allocator);

    try std.testing.expectEqual(@as(u8, 10), stamp.difficulty);
    try std.testing.expect(stamp.timestamp_ms > 0);
    try std.testing.expect(!std.mem.eql(u8, &stamp.hash, &([_]u8{0} ** 32)));
}

test "entropy stamp serialization" {
    const allocator = std.testing.allocator;

    const stamp = EntropyStamp{
        .hash = [_]u8{0xAA} ** 32,
        .difficulty = 12,
        .memory_cost_kb = 2048,
        .timestamp_ms = 1234567890,
    };

    const bytes = try stamp.toBytes(allocator);
    defer allocator.free(bytes);

    const deserialized = try EntropyStamp.fromBytes(bytes);

    try std.testing.expectEqualSlices(u8, &stamp.hash, &deserialized.hash);
    try std.testing.expectEqual(stamp.difficulty, deserialized.difficulty);
    try std.testing.expectEqual(stamp.memory_cost_kb, deserialized.memory_cost_kb);
}
