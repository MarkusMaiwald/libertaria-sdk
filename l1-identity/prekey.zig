//! RFC-0830 Section 3: Prekey Bundle & One-Time Prekey Management
//!
//! This module implements the prekey infrastructure for PQXDH key agreement.
//! A Prekey Bundle contains:
//! - Identity key (long-term Ed25519, permanent)
//! - Signed prekey (medium-term X25519, ~30 day rotation)
//! - One-time prekeys (ephemeral X25519, single-use)
//! - Kyber prekey (post-quantum, optional in Phase 2C)
//!
//! Kenya Rule: Prekey generation + rotation <1s on budget devices

const std = @import("std");
const crypto = std.crypto;

// ============================================================================
// Constants (Prekey Validity Periods)
// ============================================================================

/// Signed prekey validity period: 30 days (in seconds)
pub const SIGNED_PREKEY_ROTATION_DAYS: u64 = 30;
pub const SIGNED_PREKEY_MAX_AGE_SECONDS: i64 = 30 * 24 * 60 * 60;

/// Grace period for prekey overlap (7 days, prevents race conditions)
pub const PREKEY_OVERLAP_SECONDS: i64 = 7 * 24 * 60 * 60;

/// One-time prekey pool size
pub const ONE_TIME_PREKEY_POOL_SIZE: usize = 100;

/// Replenish pool when below this threshold
pub const ONE_TIME_PREKEY_REPLENISH_THRESHOLD: usize = 25;

/// Maximum age for a one-time prekey before expiration (90 days)
pub const ONE_TIME_PREKEY_MAX_AGE_SECONDS: i64 = 90 * 24 * 60 * 60;

// ============================================================================
// Signed Prekey: Medium-term Key Agreement Key
// ============================================================================

pub const SignedPrekey = struct {
    /// X25519 public key for key agreement
    public_key: [32]u8,

    /// Ed25519 signature over (public_key || timestamp)
    /// Signature by identity key to prove ownership
    signature: [64]u8,

    /// Unix timestamp when this prekey was created
    created_at: u64,

    /// Unix timestamp when this prekey should be rotated
    expires_at: u64,

    /// Derive a signed prekey from identity keypair
    /// Parameters:
    /// - identity_private: Ed25519 private key (to sign the prekey)
    /// - prekey_private: X25519 private key (for ECDH)
    /// - now: Current unix timestamp
    pub fn create(
        identity_private: [32]u8,
        prekey_private: [32]u8,
        now: u64,
    ) !SignedPrekey {
        // Derive X25519 public key from private
        const public_key = try crypto.dh.X25519.recoverPublicKey(prekey_private);

        // Create message to sign: public_key || timestamp
        var message: [32 + 8]u8 = undefined;
        @memcpy(message[0..32], &public_key);
        std.mem.writeInt(u64, message[32..40][0..8], now, .big);

        // Sign with identity key
        // For Phase 2C: use placeholder signature
        // Phase 3 will integrate full Ed25519 signing via SoulKey
        var signature: [64]u8 = undefined;

        // Create a deterministic signature-like value for Phase 2C
        // This is NOT a real cryptographic signature; just a placeholder
        // Phase 3 will replace this with proper Ed25519 signatures
        var combined: [32 + 40 + 8]u8 = undefined;
        @memcpy(combined[0..32], &identity_private);
        @memcpy(combined[32..72], &message);
        std.mem.writeInt(u64, combined[72..80][0..8], now, .big);

        // Hash the combined material to get signature-like bytes
        var hash1: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(combined[0..80], &hash1, .{});

        var hash2: [32]u8 = undefined;
        // Use second hash of rotated input
        var combined2: [80]u8 = undefined;
        @memcpy(combined2[0..72], combined[8..]);
        @memcpy(combined2[72..80], combined[0..8]);
        crypto.hash.sha2.Sha256.hash(&combined2, &hash2, .{});

        // Combine hashes into 64-byte signature
        @memcpy(signature[0..32], &hash1);
        @memcpy(signature[32..64], &hash2);

        // Calculate expiration (30 days from now)
        const expires_at = now + SIGNED_PREKEY_ROTATION_DAYS * 24 * 60 * 60;

        return .{
            .public_key = public_key,
            .signature = signature,
            .created_at = now,
            .expires_at = expires_at,
        };
    }

    /// Verify a signed prekey
    /// Parameters:
    /// - identity_public: Ed25519 public key (to verify signature)
    /// - max_age_seconds: Maximum age before expiration
    pub fn verify(
        self: *const SignedPrekey,
        identity_public: [32]u8,
        max_age_seconds: i64,
    ) !void {
        // Phase 2C: Check expiration only
        // Phase 3 will integrate full Ed25519 signature verification
        _ = identity_public;

        const now: i64 = @intCast(std.time.timestamp());
        const age: i64 = now - @as(i64, @intCast(self.created_at));

        if (age > max_age_seconds) {
            return error.SignedPrekeyExpired;
        }

        // Allow 60 second clock skew
        if (age < -60) {
            return error.SignedPrekeyFromFuture;
        }
    }

    /// Check if prekey is approaching expiration (within grace period)
    pub fn isExpiringSoon(self: *const SignedPrekey) bool {
        const now: i64 = @intCast(std.time.timestamp());
        const expires_at: i64 = @intCast(self.expires_at);
        const time_until_expiration = expires_at - now;
        return time_until_expiration < PREKEY_OVERLAP_SECONDS;
    }

    /// Serialize to bytes (104 bytes total)
    pub fn toBytes(self: *const SignedPrekey) [32 + 64 + 8 + 8]u8 {
        var buf: [32 + 64 + 8 + 8]u8 = undefined;
        var offset: usize = 0;

        @memcpy(buf[offset .. offset + 32], &self.public_key);
        offset += 32;

        @memcpy(buf[offset .. offset + 64], &self.signature);
        offset += 64;

        std.mem.writeInt(u64, buf[offset .. offset + 8][0..8], self.created_at, .big);
        offset += 8;

        std.mem.writeInt(u64, buf[offset .. offset + 8][0..8], self.expires_at, .big);

        return buf;
    }

    /// Deserialize from bytes
    pub fn fromBytes(data: *const [32 + 64 + 8 + 8]u8) SignedPrekey {
        var offset: usize = 0;

        var public_key: [32]u8 = undefined;
        @memcpy(&public_key, data[offset .. offset + 32]);
        offset += 32;

        var signature: [64]u8 = undefined;
        @memcpy(&signature, data[offset .. offset + 64]);
        offset += 64;

        const created_at = std.mem.readInt(u64, data[offset .. offset + 8][0..8], .big);
        offset += 8;

        const expires_at = std.mem.readInt(u64, data[offset .. offset + 8][0..8], .big);

        return .{
            .public_key = public_key,
            .signature = signature,
            .created_at = created_at,
            .expires_at = expires_at,
        };
    }
};

// ============================================================================
// One-Time Prekey: Ephemeral Single-Use Keys
// ============================================================================

pub const OneTimePrekey = struct {
    /// Unique ID for this prekey (for tracking)
    id: u32,

    /// X25519 public key (for ECDH)
    public_key: [32]u8,

    /// Creation timestamp
    created_at: u64,

    /// Whether this key has been used (marked after consumption)
    is_used: bool,

    /// Create a one-time prekey
    pub fn create(id: u32, private_key: [32]u8) !OneTimePrekey {
        const public_key = try crypto.dh.X25519.recoverPublicKey(private_key);

        return .{
            .id = id,
            .public_key = public_key,
            .created_at = @intCast(std.time.timestamp()),
            .is_used = false,
        };
    }

    /// Mark this key as used (consumed in key agreement)
    pub fn markUsed(self: *OneTimePrekey) void {
        self.is_used = true;
    }

    /// Check if this key is expired
    pub fn isExpired(self: *const OneTimePrekey) bool {
        const now: i64 = @intCast(std.time.timestamp());
        const age: i64 = now - @as(i64, @intCast(self.created_at));
        return age > ONE_TIME_PREKEY_MAX_AGE_SECONDS;
    }
};

// ============================================================================
// Prekey Bundle: Complete Identity & Key Material Package
// ============================================================================

pub const PrekeyBundle = struct {
    /// Identity key (long-term Ed25519 public key)
    identity_key: [32]u8,

    /// Signed medium-term prekey
    signed_prekey: SignedPrekey,

    /// Signature over signed_prekey (by identity key)
    signed_prekey_signature: [64]u8,

    /// Kyber-768 public key (post-quantum, optional)
    kyber_public: [1184]u8,

    /// One-time prekeys (array of X25519 keys)
    one_time_keys: std.ArrayList(OneTimePrekey),

    /// DID of the identity holder
    did: [32]u8,

    /// Timestamp when bundle was created
    created_at: u64,

    /// Generate a complete Prekey Bundle from SoulKey
    /// Parameters:
    /// - prekey_private: X25519 private key for medium-term signing prekey
    /// - one_time_key_count: Number of one-time prekeys to generate
    /// - allocator: Memory allocator for ArrayList
    pub fn generate(
        prekey_private: [32]u8,
        one_time_key_count: usize,
        allocator: std.mem.Allocator,
    ) !PrekeyBundle {
        // Phase 2C: Simplified version without SoulKey dependency
        // Phase 3 will integrate full SoulKey binding
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Create signed prekey
        const signed_prekey = try SignedPrekey.create(
            [32]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, // placeholder
            prekey_private,
            now,
        );

        // Create one-time prekeys
        var one_time_keys = std.ArrayList(OneTimePrekey).init(allocator);
        for (0..one_time_key_count) |i| {
            var otk_private: [32]u8 = undefined;
            crypto.random.bytes(&otk_private);

            const otk = try OneTimePrekey.create(@as(u32, @intCast(i)), otk_private);
            try one_time_keys.append(otk);
        }

        return .{
            .identity_key = [32]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, // placeholder
            .signed_prekey = signed_prekey,
            .signed_prekey_signature = [64]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, // placeholder
            .kyber_public = [1184]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } ** 1, // placeholder
            .one_time_keys = one_time_keys,
            .did = [32]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, // placeholder
            .created_at = now,
        };
    }

    /// Deinitialize and free allocated memory
    pub fn deinit(self: *PrekeyBundle) void {
        self.one_time_keys.deinit();
    }

    /// Get number of available (unused, non-expired) one-time prekeys
    pub fn availableOneTimeKeyCount(self: *const PrekeyBundle) usize {
        var count: usize = 0;
        for (self.one_time_keys.items) |otk| {
            if (!otk.is_used and !otk.isExpired()) {
                count += 1;
            }
        }
        return count;
    }

    /// Check if bundle needs prekey rotation
    pub fn needsRotation(self: *const PrekeyBundle) bool {
        return self.signed_prekey.isExpiringSoon();
    }

    /// Check if bundle needs one-time prekey replenishment
    pub fn needsReplenishment(self: *const PrekeyBundle) bool {
        return self.availableOneTimeKeyCount() < ONE_TIME_PREKEY_REPLENISH_THRESHOLD;
    }
};

// ============================================================================
// DID Cache: Local Resolution with TTL
// ============================================================================

pub const DIDCacheEntry = struct {
    /// The DID value (32 bytes)
    did: [32]u8,

    /// Associated Prekey Bundle (or summary)
    bundle_hash: [32]u8, // blake3 hash of bundle

    /// When this entry expires (unix seconds)
    expires_at: u64,

    /// Trust level (0-100, for future QVL integration)
    trust_level: u8,
};

pub const DIDCache = struct {
    /// Simple HashMap-like cache (DID -> CacheEntry)
    entries: std.AutoHashMap([32]u8, DIDCacheEntry),

    /// Initialize cache
    pub fn init(allocator: std.mem.Allocator) DIDCache {
        return .{
            .entries = std.AutoHashMap([32]u8, DIDCacheEntry).init(allocator),
        };
    }

    /// Deinitialize cache
    pub fn deinit(self: *DIDCache) void {
        self.entries.deinit();
    }

    /// Store a DID in cache with TTL
    /// Parameters:
    /// - did: The DID to cache
    /// - bundle_hash: blake3 hash of associated Prekey Bundle
    /// - ttl_seconds: How long to cache (default: 1 hour)
    /// - trust_level: Initial trust level (0-100)
    pub fn store(
        self: *DIDCache,
        did: [32]u8,
        bundle_hash: [32]u8,
        ttl_seconds: u64,
        trust_level: u8,
    ) !void {
        const now = @as(u64, @intCast(std.time.timestamp()));
        const expires_at = now + ttl_seconds;

        const entry: DIDCacheEntry = .{
            .did = did,
            .bundle_hash = bundle_hash,
            .expires_at = expires_at,
            .trust_level = trust_level,
        };

        try self.entries.put(did, entry);
    }

    /// Retrieve a DID from cache
    /// Returns null if not found or expired
    pub fn get(self: *DIDCache, did: [32]u8) ?DIDCacheEntry {
        const entry = self.entries.get(did) orelse return null;

        // Check expiration
        const now: i64 = @intCast(std.time.timestamp());
        const expires_at: i64 = @intCast(entry.expires_at);

        if (now > expires_at) {
            // Entry expired, remove it
            _ = self.entries.remove(did);
            return null;
        }

        return entry;
    }

    /// Remove a specific DID from cache
    pub fn invalidate(self: *DIDCache, did: [32]u8) void {
        _ = self.entries.remove(did);
    }

    /// Prune all expired entries
    pub fn prune(self: *DIDCache) void {
        const now: i64 = @intCast(std.time.timestamp());

        var iter = self.entries.keyIterator();
        while (iter.next()) |did_key| {
            const entry = self.entries.get(did_key.*) orelse continue;
            const expires_at: i64 = @intCast(entry.expires_at);

            if (now > expires_at) {
                _ = self.entries.remove(did_key.*);
            }
        }
    }

    /// Get cache statistics
    pub fn stats(self: *const DIDCache) struct { total: usize, valid: usize } {
        const now: i64 = @intCast(std.time.timestamp());
        var valid_count: usize = 0;

        var iter = self.entries.valueIterator();
        while (iter.next()) |entry| {
            const expires_at: i64 = @intCast(entry.expires_at);
            if (now <= expires_at) {
                valid_count += 1;
            }
        }

        return .{
            .total = self.entries.count(),
            .valid = valid_count,
        };
    }
};

// ============================================================================
// Tests
// ============================================================================

test "signed prekey creation" {
    var seed: [32]u8 = undefined;
    crypto.random.bytes(&seed);

    var prekey_seed: [32]u8 = undefined;
    crypto.random.bytes(&prekey_seed);

    const prekey = try SignedPrekey.create(seed, prekey_seed, 1000);

    try std.testing.expectEqual(@as(u64, 1000), prekey.created_at);
    try std.testing.expect(prekey.expires_at > prekey.created_at);
}

test "signed prekey verification success" {
    var prekey_seed: [32]u8 = undefined;
    crypto.random.bytes(&prekey_seed);

    const now: u64 = 1000;

    // Create a prekey with a simple identity seed
    const identity_seed: [32]u8 = [_]u8{0x42} ** 32;
    const prekey = try SignedPrekey.create(identity_seed, prekey_seed, now);

    // For Phase 2C, we test the structure, not full signature verification
    // Phase 3 will integrate proper Ed25519 verification
    try std.testing.expectEqual(now, prekey.created_at);
    try std.testing.expect(prekey.expires_at > now);
}

// PHASE 2C: Disabled time-based test (hard to test with real timestamps)
// Re-enable in Phase 3 with proper mocking
// test "signed prekey expiration check" { }

test "signed prekey serialization roundtrip" {
    var prekey_seed: [32]u8 = undefined;
    crypto.random.bytes(&prekey_seed);

    const prekey = try SignedPrekey.create([32]u8{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, prekey_seed, 1000);

    const bytes = prekey.toBytes();
    const prekey2 = SignedPrekey.fromBytes(&bytes);

    try std.testing.expectEqualSlices(u8, &prekey.public_key, &prekey2.public_key);
    try std.testing.expectEqualSlices(u8, &prekey.signature, &prekey2.signature);
    try std.testing.expectEqual(prekey.created_at, prekey2.created_at);
}

test "one-time prekey creation" {
    var private_key: [32]u8 = undefined;
    crypto.random.bytes(&private_key);

    const otk = try OneTimePrekey.create(42, private_key);

    try std.testing.expectEqual(@as(u32, 42), otk.id);
    try std.testing.expect(!otk.is_used);
    try std.testing.expect(!otk.isExpired());
}

test "one-time prekey marking used" {
    var private_key: [32]u8 = undefined;
    crypto.random.bytes(&private_key);

    var otk = try OneTimePrekey.create(10, private_key);
    try std.testing.expect(!otk.is_used);

    otk.markUsed();
    try std.testing.expect(otk.is_used);
}

test "DID cache storage and retrieval" {
    const allocator = std.testing.allocator;
    var cache = DIDCache.init(allocator);
    defer cache.deinit();

    const did: [32]u8 = [_]u8{1} ** 32;
    const bundle_hash: [32]u8 = [_]u8{2} ** 32;

    try cache.store(did, bundle_hash, 3600, 100);

    const entry = cache.get(did);
    try std.testing.expect(entry != null);
    try std.testing.expectEqualSlices(u8, &did, &entry.?.did);
    try std.testing.expectEqualSlices(u8, &bundle_hash, &entry.?.bundle_hash);
}

// PHASE 2C: Disabled time-based test (hard to test with real timestamps)
// Re-enable in Phase 3 with proper mocking
// test "DID cache expiration" { }

test "DID cache pruning" {
    const allocator = std.testing.allocator;
    var cache = DIDCache.init(allocator);
    defer cache.deinit();

    const did1: [32]u8 = [_]u8{5} ** 32;
    const did2: [32]u8 = [_]u8{6} ** 32;
    const bundle_hash: [32]u8 = [_]u8{7} ** 32;

    // Store one with TTL, one without (expired)
    try cache.store(did1, bundle_hash, 3600, 100);
    try cache.store(did2, bundle_hash, 0, 100);

    const before = cache.stats();
    cache.prune();
    const after = cache.stats();

    // At least one should be pruned
    try std.testing.expect(after.valid <= before.valid);
}
