//! RFC-0250: Larval Identity / SoulKey
//!
//! This module implements SoulKey - the core identity keypair for Libertaria.
//!
//! A SoulKey is a cryptographic identity consisting of three keypairs:
//! 1. Ed25519 - Digital signatures (sign messages)
//! 2. X25519 - Elliptic curve key agreement (ECDH)
//! 3. ML-KEM-768 - Post-quantum key encapsulation (hybrid)
//!
//! The identity is cryptographically bound to a DID (Decentralized Identifier)
//! via a SHA256 hash of the public keys.
//!
//! Storage: Private keys MUST be protected (hardware wallet, TPM, or secure enclave)

const std = @import("std");
const crypto = std.crypto;
const pqxdh = @import("pqxdh.zig");

// ============================================================================
// SoulKey: Core Identity Keypair
// ============================================================================

pub const SoulKey = struct {
    /// Ed25519 signing keypair
    ed25519_private: [32]u8,
    ed25519_public: [32]u8,

    /// X25519 key agreement keypair
    x25519_private: [32]u8,
    x25519_public: [32]u8,

    /// ML-KEM-768 post-quantum keypair
    /// (populated deterministically from seed via liboqs)
    mlkem_private: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8,
    mlkem_public: [pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8,

    /// DID: SHA256 hash of (ed25519_public || x25519_public || mlkem_public)
    did: [32]u8,

    /// Generation timestamp (unix seconds)
    created_at: u64,

    // === Methods ===

    /// Generate a new SoulKey from seed (deterministic, BIP-39 compatible)
    pub fn fromSeed(seed: *const [32]u8) !SoulKey {
        var key: SoulKey = undefined;

        // === Ed25519 generation ===
        // Properly derive keypair from seed using standard Ed25519
        const ed_kp = try crypto.sign.Ed25519.KeyPair.generateDeterministic(seed.*);
        // ed_kp.secret_key.seed() returns the seed used.
        key.ed25519_private = ed_kp.secret_key.seed();
        key.ed25519_public = ed_kp.public_key.bytes;

        // === X25519 generation ===
        // Derive X25519 private from seed via domain-separated hashing
        var x25519_seed: [32]u8 = undefined;
        // Simple domain separation: hash seed || domain string
        // String "libertaria-soulkey-x25519-v1" is 28 bytes
        var input_with_domain: [32 + 28]u8 = undefined;
        @memcpy(input_with_domain[0..32], seed);
        @memcpy(input_with_domain[32..60], "libertaria-soulkey-x25519-v1");
        crypto.hash.sha2.Sha256.hash(&input_with_domain, &x25519_seed, .{});
        key.x25519_private = x25519_seed;
        key.x25519_public = try crypto.dh.X25519.recoverPublicKey(x25519_seed);

        // === ML-KEM-768 generation ===
        // Derive dedicated seed for ML-KEM to ensure domain separation
        var mlkem_seed: [32]u8 = undefined;
        var mlkem_input: [32 + 30]u8 = undefined;
        @memcpy(mlkem_input[0..32], seed);
        @memcpy(mlkem_input[32..62], "libertaria-soulkey-mlkem768-v1");
        crypto.hash.sha2.Sha256.hash(&mlkem_input, &mlkem_seed, .{});

        // Use custom thread-safe deterministic generation (via liboqs RNG override)
        // Note: This relies on liboqs being linked via build.zig
        const kp = try pqxdh.generateKeypairFromSeed(mlkem_seed);
        key.mlkem_public = kp.public_key;
        key.mlkem_private = kp.secret_key;

        // === DID generation ===
        // Hash all public keys together: ed25519 || x25519 || mlkem
        // Using SHA256
        var did_input: [32 + 32 + pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8 = undefined;
        @memcpy(did_input[0..32], &key.ed25519_public);
        @memcpy(did_input[32..64], &key.x25519_public);
        @memcpy(did_input[64..], &key.mlkem_public);
        crypto.hash.sha2.Sha256.hash(&did_input, &key.did, .{});

        key.created_at = @intCast(std.time.timestamp());

        return key;
    }

    /// Generate a new SoulKey with random seed
    pub fn generate() !SoulKey {
        var seed: [32]u8 = undefined;
        crypto.random.bytes(&seed);
        defer crypto.secureZero(u8, &seed);
        return fromSeed(&seed);
    }

    /// Sign a message using Ed25519
    pub fn sign(self: *const SoulKey, message: []const u8) ![64]u8 {
        // Reconstruct KeyPair from stored seed/public
        // Note: Ed25519.KeyPair can be formed from just seed if needed, but we have both.
        const kp = try crypto.sign.Ed25519.KeyPair.generateDeterministic(self.ed25519_private);
        // Verify public matches? (Optional sanity check)

        const signature = try kp.sign(message, null);
        return signature.toBytes();
    }

    /// Verify a signature using Ed25519
    pub fn verify(public_key: [32]u8, message: []const u8, signature: [64]u8) !bool {
        const sig = crypto.sign.Ed25519.Signature.fromBytes(signature);
        const pk = crypto.sign.Ed25519.PublicKey.fromBytes(public_key) catch return false;

        sig.verify(message, pk) catch return false;
        return true;
    }

    /// Derive a shared secret via X25519 key agreement
    pub fn deriveSharedSecret(self: *const SoulKey, peer_public: [32]u8) ![32]u8 {
        return crypto.dh.X25519.scalarmult(self.x25519_private, peer_public);
    }

    /// Serialize SoulKey to bytes (includes all key material)
    /// WARNING: This exposes private keys! Only use for secure storage.
    pub fn toBytes(self: *const SoulKey, allocator: std.mem.Allocator) ![]u8 {
        const total_size = 32 + 32 + 32 + 32 + 2400 + 1184 + 32 + 8;
        var buffer = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        @memcpy(buffer[offset .. offset + 32], &self.ed25519_private);
        offset += 32;

        @memcpy(buffer[offset .. offset + 32], &self.ed25519_public);
        offset += 32;

        @memcpy(buffer[offset .. offset + 32], &self.x25519_private);
        offset += 32;

        @memcpy(buffer[offset .. offset + 32], &self.x25519_public);
        offset += 32;

        @memcpy(buffer[offset .. offset + 2400], &self.mlkem_private);
        offset += 2400;

        @memcpy(buffer[offset .. offset + 1184], &self.mlkem_public);
        offset += 1184;

        @memcpy(buffer[offset .. offset + 32], &self.did);
        offset += 32;

        @memcpy(
            buffer[offset .. offset + 8],
            std.mem.asBytes(&std.mem.nativeToBig(u64, self.created_at)),
        );

        return buffer;
    }

    /// Deserialize SoulKey from bytes
    pub fn fromBytes(data: []const u8) !SoulKey {
        const expected_size = 32 + 32 + 32 + 32 + 2400 + 1184 + 32 + 8;
        if (data.len != expected_size) return error.InvalidSoulKeySize;

        var key: SoulKey = undefined;
        var offset: usize = 0;

        @memcpy(&key.ed25519_private, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&key.ed25519_public, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&key.x25519_private, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&key.x25519_public, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&key.mlkem_private, data[offset .. offset + 2400]);
        offset += 2400;

        @memcpy(&key.mlkem_public, data[offset .. offset + 1184]);
        offset += 1184;

        @memcpy(&key.did, data[offset .. offset + 32]);
        offset += 32;

        key.created_at = std.mem.readInt(u64, data[offset .. offset + 8][0..8], .big);

        return key;
    }

    /// Zeroize private key material (constant-time)
    pub fn zeroize(self: *SoulKey) void {
        crypto.secureZero(u8, &self.ed25519_private);
        crypto.secureZero(u8, &self.x25519_private);
        crypto.secureZero(u8, &self.mlkem_private);
    }

    /// Get the DID string (base58 or hex)
    pub fn didString(self: *const SoulKey, allocator: std.mem.Allocator) ![]u8 {
        // For now, return hex-encoded DID
        return std.fmt.allocPrint(allocator, "did:libertaria:{s}", .{std.fmt.fmtSliceHexLower(&self.did)});
    }
};

// ============================================================================
// DID: Decentralized Identifier
// ============================================================================

pub const DID = struct {
    /// Raw DID bytes (32-byte SHA256 hash of all public keys)
    bytes: [32]u8,

    /// Create DID from public keys
    /// Hash: SHA256(ed25519_public || x25519_public || mlkem_public)
    pub fn create(ed25519_public: [32]u8, x25519_public: [32]u8, mlkem_public: [1184]u8) DID {
        var did_input: [32 + 32 + 1184]u8 = undefined;
        @memcpy(did_input[0..32], &ed25519_public);
        @memcpy(did_input[32..64], &x25519_public);
        @memcpy(did_input[64..1248], &mlkem_public);

        var bytes: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&did_input, &bytes, .{});

        return .{ .bytes = bytes };
    }

    /// Hex-encode DID for display
    pub fn hexString(self: *const DID, allocator: std.mem.Allocator) ![]u8 {
        return std.fmt.allocPrint(allocator, "did:libertaria:{s}", .{std.fmt.fmtSliceHexLower(&self.bytes)});
    }
};

// ============================================================================
// Tests
// ============================================================================

test "soulkey generation" {
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    const key = try SoulKey.fromSeed(&seed);

    try std.testing.expectEqual(@as(usize, 32), key.ed25519_public.len);
    try std.testing.expectEqual(@as(usize, 32), key.x25519_public.len);
    try std.testing.expectEqual(@as(usize, 32), key.did.len);
}

test "soulkey signature" {
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    const key = try SoulKey.fromSeed(&seed);
    const message = "Hello, Libertaria!";

    const signature = try key.sign(message);
    const valid = try SoulKey.verify(key.ed25519_public, message, signature);

    try std.testing.expect(valid);
}

test "soulkey serialization" {
    const allocator = std.testing.allocator;

    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    const key = try SoulKey.fromSeed(&seed);
    const bytes = try key.toBytes(allocator);
    defer allocator.free(bytes);

    const key2 = try SoulKey.fromBytes(bytes);

    try std.testing.expectEqualSlices(u8, &key.ed25519_public, &key2.ed25519_public);
    try std.testing.expectEqualSlices(u8, &key.x25519_public, &key2.x25519_public);
    try std.testing.expectEqualSlices(u8, &key.did, &key2.did);
}

test "did creation" {
    var seed: [32]u8 = undefined;
    std.crypto.random.bytes(&seed);

    const key = try SoulKey.fromSeed(&seed);
    const did = DID.create(key.ed25519_public, key.x25519_public, key.mlkem_public);

    try std.testing.expectEqualSlices(u8, &key.did, &did.bytes);
}

test "SoulKey deterministic generation" {
    var seed: [32]u8 = [_]u8{0x42} ** 32;

    const key1 = try SoulKey.fromSeed(&seed);
    const key2 = try SoulKey.fromSeed(&seed);

    try std.testing.expectEqualSlices(u8, &key1.ed25519_private, &key2.ed25519_private);
    try std.testing.expectEqualSlices(u8, &key1.ed25519_public, &key2.ed25519_public);
    try std.testing.expectEqualSlices(u8, &key1.x25519_private, &key2.x25519_private);
    try std.testing.expectEqualSlices(u8, &key1.x25519_public, &key2.x25519_public);
    try std.testing.expectEqualSlices(u8, &key1.mlkem_private, &key2.mlkem_private);
    try std.testing.expectEqualSlices(u8, &key1.mlkem_public, &key2.mlkem_public);
    try std.testing.expectEqualSlices(u8, &key1.did, &key2.did);
}

test "SoulKey signing and verification" {
    const key = try SoulKey.generate();
    const message = "Hello, Libertaria!";

    const signature = try key.sign(message);
    const valid = try SoulKey.verify(key.ed25519_public, message, signature);

    try std.testing.expect(valid);

    // Check invalid signature
    var invalid_sig = signature;
    invalid_sig[0] ^= 0xFF; // Flip a bit
    const invalid = try SoulKey.verify(key.ed25519_public, message, invalid_sig);
    try std.testing.expect(!invalid);
}
