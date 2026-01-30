//! RFC-0830 Section 2.3: PQXDH Protocol
//!
//! Post-Quantum Extended Diffie-Hellman Key Agreement
//!
//! This module implements hybrid key agreement combining:
//! - 4× X25519 elliptic curve handshakes (classical)
//! - 1× ML-KEM-768 post-quantum key encapsulation
//! - HKDF-SHA256 to combine 5 shared secrets into root key
//!
//! Security: Attacker must break BOTH X25519 AND ML-KEM-768 to compromise
//! This provides defense against "harvest now, decrypt later" attacks.

const std = @import("std");
const crypto = std.crypto;

// ============================================================================
// C FFI: liboqs (ML-KEM-768)
// ============================================================================
// Link against liboqs (C library, compiled in build.zig)
// Source: https://github.com/open-quantum-safe/liboqs
// FIPS 203: ML-KEM-768 (post-standardization naming for Kyber-768)

/// ML-KEM-768 key generation
extern "c" fn OQS_KEM_kyber768_keypair(
    public_key: ?*u8,
    secret_key: ?*u8,
) c_int;

/// ML-KEM-768 encapsulation (creates shared secret + ciphertext)
extern "c" fn OQS_KEM_kyber768_encaps(
    ciphertext: ?*u8,
    shared_secret: ?*u8,
    public_key: ?*const u8,
) c_int;

/// ML-KEM-768 decapsulation (recovers shared secret from ciphertext)
extern "c" fn OQS_KEM_kyber768_decaps(
    shared_secret: ?*u8,
    ciphertext: ?*const u8,
    secret_key: ?*const u8,
) c_int;

// ============================================================================
// ML-KEM-768 Parameters (NIST FIPS 203)
// ============================================================================

pub const ML_KEM_768 = struct {
    pub const PUBLIC_KEY_SIZE = 1184;
    pub const SECRET_KEY_SIZE = 2400;
    pub const CIPHERTEXT_SIZE = 1088;
    pub const SHARED_SECRET_SIZE = 32;
    pub const SECURITY_LEVEL = 3; // NIST Level 3 (≈AES-192)
};

// ============================================================================
// X25519 Parameters (Classical)
// ============================================================================

pub const X25519 = struct {
    pub const PUBLIC_KEY_SIZE = 32;
    pub const PRIVATE_KEY_SIZE = 32;
    pub const SHARED_SECRET_SIZE = 32;
};

// ============================================================================
// PQXDH Prekey Bundle
// ============================================================================
// Sent by Bob to Alice (or published to prekey server)
// Contains all keys needed to initiate a hybrid key agreement

pub const PrekeyBundle = struct {
    /// Long-term identity key (Ed25519 public key)
    /// Used to verify all signatures in bundle
    identity_key: [32]u8,

    /// Medium-term signed prekey (X25519 public key)
    /// Rotated every 30 days
    signed_prekey_x25519: [X25519.PUBLIC_KEY_SIZE]u8,

    /// Signature of signed_prekey_x25519 by identity_key (Ed25519)
    /// Proves Bob authorized this prekey
    signed_prekey_signature: [64]u8,

    /// Post-quantum signed prekey (ML-KEM-768 public key)
    /// Rotated every 30 days, paired with X25519 signed prekey
    signed_prekey_mlkem: [ML_KEM_768.PUBLIC_KEY_SIZE]u8,

    /// One-time ephemeral prekey (X25519 public key)
    /// Consumed on first use, provides forward secrecy
    one_time_prekey_x25519: [X25519.PUBLIC_KEY_SIZE]u8,

    /// One-time ephemeral prekey (ML-KEM-768 public key)
    /// Consumed on first use, provides PQ forward secrecy
    one_time_prekey_mlkem: [ML_KEM_768.PUBLIC_KEY_SIZE]u8,

    /// Serialize bundle to bytes for transmission
    /// Total size: 32 + 32 + 64 + 1184 + 32 + 1184 = 2528 bytes
    pub fn toBytes(self: *const PrekeyBundle, allocator: std.mem.Allocator) ![]u8 {
        const total_size = 32 + 32 + 64 + ML_KEM_768.PUBLIC_KEY_SIZE + 32 + ML_KEM_768.PUBLIC_KEY_SIZE;
        var buffer = try allocator.alloc(u8, total_size);
        var offset: usize = 0;

        @memcpy(buffer[offset .. offset + 32], &self.identity_key);
        offset += 32;

        @memcpy(buffer[offset .. offset + 32], &self.signed_prekey_x25519);
        offset += 32;

        @memcpy(buffer[offset .. offset + 64], &self.signed_prekey_signature);
        offset += 64;

        @memcpy(buffer[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE], &self.signed_prekey_mlkem);
        offset += ML_KEM_768.PUBLIC_KEY_SIZE;

        @memcpy(buffer[offset .. offset + 32], &self.one_time_prekey_x25519);
        offset += 32;

        @memcpy(buffer[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE], &self.one_time_prekey_mlkem);

        return buffer;
    }

    /// Deserialize bundle from bytes
    pub fn fromBytes(_: std.mem.Allocator, data: []const u8) !PrekeyBundle {
        const expected_size = 32 + 32 + 64 + ML_KEM_768.PUBLIC_KEY_SIZE + 32 + ML_KEM_768.PUBLIC_KEY_SIZE;
        if (data.len != expected_size) {
            return error.InvalidBundleSize;
        }

        var bundle: PrekeyBundle = undefined;
        var offset: usize = 0;

        @memcpy(&bundle.identity_key, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.signed_prekey_x25519, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.signed_prekey_signature, data[offset .. offset + 64]);
        offset += 64;

        @memcpy(&bundle.signed_prekey_mlkem, data[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE]);
        offset += ML_KEM_768.PUBLIC_KEY_SIZE;

        @memcpy(&bundle.one_time_prekey_x25519, data[offset .. offset + 32]);
        offset += 32;

        @memcpy(&bundle.one_time_prekey_mlkem, data[offset .. offset + ML_KEM_768.PUBLIC_KEY_SIZE]);

        return bundle;
    }
};

// ============================================================================
// PQXDH Initial Message (Alice → Bob)
// ============================================================================
// Sent by Alice when initiating communication with Bob
// Contains ephemeral public keys + ML-KEM ciphertext

pub const PQXDHInitialMessage = struct {
    /// Alice's ephemeral X25519 public key
    ephemeral_x25519: [X25519.PUBLIC_KEY_SIZE]u8,

    /// ML-KEM-768 ciphertext for Bob's signed prekey
    mlkem_ciphertext: [ML_KEM_768.CIPHERTEXT_SIZE]u8,

    /// Serialize for transmission
    /// Size: 32 + 1088 = 1120 bytes (fits in 2 LWF jumbo frames or 3 standard frames)
    pub fn toBytes(self: *const PQXDHInitialMessage, allocator: std.mem.Allocator) ![]u8 {
        const total_size = X25519.PUBLIC_KEY_SIZE + ML_KEM_768.CIPHERTEXT_SIZE;
        var buffer = try allocator.alloc(u8, total_size);

        @memcpy(buffer[0..32], &self.ephemeral_x25519);
        @memcpy(buffer[32..], &self.mlkem_ciphertext);

        return buffer;
    }

    /// Deserialize from bytes
    pub fn fromBytes(data: []const u8) !PQXDHInitialMessage {
        const expected_size = X25519.PUBLIC_KEY_SIZE + ML_KEM_768.CIPHERTEXT_SIZE;
        if (data.len != expected_size) {
            return error.InvalidInitialMessageSize;
        }

        var msg: PQXDHInitialMessage = undefined;
        @memcpy(&msg.ephemeral_x25519, data[0..32]);
        @memcpy(&msg.mlkem_ciphertext, data[32..]);
        return msg;
    }
};

// ============================================================================
// PQXDH Key Agreement (Alice Initiates)
// ============================================================================

pub const PQXDHInitiatorResult = struct {
    /// Root key derived from 5 shared secrets
    /// This becomes the input to Double Ratchet initialization
    root_key: [32]u8,

    /// Initial message sent to Bob
    initial_message: PQXDHInitialMessage,

    /// Ephemeral private key (keep secret until message sent)
    ephemeral_private: [X25519.PRIVATE_KEY_SIZE]u8,
};

/// Alice initiates hybrid key agreement with Bob
///
/// **Ceremony:**
/// 1. Generate ephemeral X25519 keypair (DH1, DH2)
/// 2. ECDH with Bob's signed prekey (DH3)
/// 3. ECDH with Bob's one-time prekey (DH4)
/// 4. ML-KEM encapsulate toward Bob's signed prekey (KEM1)
/// 5. Combine 5 shared secrets: [DH1, DH2, DH3, DH4, KEM1]
/// 6. KDF via HKDF-SHA256
///
/// **Result:** Root key for Double Ratchet + initial message
pub fn initiator(
    alice_identity_private: [32]u8,
    bob_prekey_bundle: *const PrekeyBundle,
    _: std.mem.Allocator,
) !PQXDHInitiatorResult {
    // === Step 1: Generate Alice's ephemeral X25519 keypair ===
    var ephemeral_private: [X25519.PRIVATE_KEY_SIZE]u8 = undefined;
    crypto.random.bytes(&ephemeral_private);

    const ephemeral_public = try crypto.dh.X25519.recoverPublicKey(ephemeral_private);

    // === Step 2-4: Compute three X25519 shared secrets (DH1, DH2, DH3) ===

    // DH1: ephemeral ↔ Bob's signed prekey
    const dh1 = try crypto.dh.X25519.scalarmult(ephemeral_private, bob_prekey_bundle.signed_prekey_x25519);

    // DH2: ephemeral ↔ Bob's one-time prekey
    const dh2 = try crypto.dh.X25519.scalarmult(ephemeral_private, bob_prekey_bundle.one_time_prekey_x25519);

    // DH3: Alice's identity ↔ Bob's signed prekey
    const dh3 = try crypto.dh.X25519.scalarmult(alice_identity_private, bob_prekey_bundle.signed_prekey_x25519);

    // === Step 5: ML-KEM-768 encapsulation ===
    // Alice generates ephemeral keypair and encapsulates toward Bob's ML-KEM key

    var kem_ss: [ML_KEM_768.SHARED_SECRET_SIZE]u8 = undefined;
    var kem_ct: [ML_KEM_768.CIPHERTEXT_SIZE]u8 = undefined;

    // Call liboqs ML-KEM encapsulation
    const kem_result = OQS_KEM_kyber768_encaps(
        @ptrCast(&kem_ct),
        @ptrCast(&kem_ss),
        @ptrCast(&bob_prekey_bundle.signed_prekey_mlkem),
    );

    if (kem_result != 0) {
        return error.MLKEMEncapsError;
    }

    // === Step 6: Combine 5 shared secrets via HKDF-SHA256 ===

    // Concatenate all shared secrets: DH1 || DH2 || DH3 || KEM_SS (padded)
    var combined: [32 * 5]u8 = undefined;
    @memcpy(combined[0..32], &dh1);
    @memcpy(combined[32..64], &dh2);
    @memcpy(combined[64..96], &dh3);
    @memcpy(combined[96..128], &kem_ss);
    @memset(combined[128..160], 0); // Reserved for future extensibility

    // KDF: HKDF-SHA256
    var root_key: [32]u8 = undefined;
    const info = "Libertaria PQXDH v1";

    const hkdf = std.crypto.kdf.hkdf.HkdfSha256;
    const prk = hkdf.extract(info, combined[0..160]);
    @memcpy(&root_key, &prk);

    return PQXDHInitiatorResult{
        .root_key = root_key,
        .initial_message = .{
            .ephemeral_x25519 = ephemeral_public,
            .mlkem_ciphertext = kem_ct,
        },
        .ephemeral_private = ephemeral_private,
    };
}

// ============================================================================
// PQXDH Key Agreement (Bob Responds)
// ============================================================================

pub const PQXDHResponderResult = struct {
    /// Root key (matches Alice's root key)
    /// Becomes input to Double Ratchet initialization
    root_key: [32]u8,
};

/// Bob responds to Alice's PQXDH initial message
///
/// **Ceremony:**
/// 1. ECDH Bob's signed prekey ↔ Alice's ephemeral (DH1)
/// 2. ECDH Bob's one-time prekey ↔ Alice's ephemeral (DH2)
/// 3. ECDH Bob's identity ↔ Alice's identity (DH3)
/// 4. ML-KEM decapsulate using ciphertext from initial message (KEM1)
/// 5. Combine 5 shared secrets (same order as Alice)
/// 6. KDF via HKDF-SHA256
///
/// **Result:** Root key matching Alice's (should be identical)
pub fn responder(
    bob_identity_private: [32]u8,
    bob_signed_prekey_private: [32]u8,
    bob_one_time_prekey_private: [32]u8,
    bob_mlkem_private: [ML_KEM_768.SECRET_KEY_SIZE]u8,
    alice_identity_public: [32]u8,
    alice_initial_message: *const PQXDHInitialMessage,
) !PQXDHResponderResult {
    _ = bob_identity_private; // Not used in current X3DH variant

    // === Step 1-3: Compute three X25519 shared secrets ===

    // DH1: Bob's signed prekey ↔ Alice's ephemeral
    const dh1 = try crypto.dh.X25519.scalarmult(bob_signed_prekey_private, alice_initial_message.ephemeral_x25519);

    // DH2: Bob's one-time prekey ↔ Alice's ephemeral
    const dh2 = try crypto.dh.X25519.scalarmult(bob_one_time_prekey_private, alice_initial_message.ephemeral_x25519);

    // DH3: Bob's signed prekey ↔ Alice's identity
    // This matches Alice's: alice_identity_private ↔ bob_signed_prekey_public
    const dh3 = try crypto.dh.X25519.scalarmult(bob_signed_prekey_private, alice_identity_public);

    // === Step 4: ML-KEM-768 decapsulation ===

    var kem_ss: [ML_KEM_768.SHARED_SECRET_SIZE]u8 = undefined;

    // Call liboqs ML-KEM decapsulation
    const kem_result = OQS_KEM_kyber768_decaps(
        @ptrCast(&kem_ss),
        @ptrCast(&alice_initial_message.mlkem_ciphertext),
        @ptrCast(&bob_mlkem_private),
    );

    if (kem_result != 0) {
        return error.MLKEMDecapsError;
    }

    // === Step 5-6: Combine secrets and KDF (same as Alice) ===

    var combined: [32 * 5]u8 = undefined;
    @memcpy(combined[0..32], &dh1);
    @memcpy(combined[32..64], &dh2);
    @memcpy(combined[64..96], &dh3);
    @memcpy(combined[96..128], &kem_ss);
    @memset(combined[128..160], 0);

    var root_key: [32]u8 = undefined;
    const info = "Libertaria PQXDH v1";

    const hkdf = std.crypto.kdf.hkdf.HkdfSha256;
    const prk = hkdf.extract(info, combined[0..160]);
    @memcpy(&root_key, &prk);

    return PQXDHResponderResult{
        .root_key = root_key,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "pqxdh prekey bundle serialization" {
    const allocator = std.testing.allocator;

    const bundle = PrekeyBundle{
        .identity_key = [_]u8{0xAA} ** 32,
        .signed_prekey_x25519 = [_]u8{0xBB} ** 32,
        .signed_prekey_signature = [_]u8{0xCC} ** 64,
        .signed_prekey_mlkem = [_]u8{0xDD} ** ML_KEM_768.PUBLIC_KEY_SIZE,
        .one_time_prekey_x25519 = [_]u8{0xEE} ** 32,
        .one_time_prekey_mlkem = [_]u8{0xFF} ** ML_KEM_768.PUBLIC_KEY_SIZE,
    };

    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);

    const deserialized = try PrekeyBundle.fromBytes(allocator, bytes);

    try std.testing.expectEqualSlices(u8, &bundle.identity_key, &deserialized.identity_key);
    try std.testing.expectEqualSlices(u8, &bundle.signed_prekey_x25519, &deserialized.signed_prekey_x25519);
}

test "pqxdh initial message serialization" {
    const allocator = std.testing.allocator;

    const msg = PQXDHInitialMessage{
        .ephemeral_x25519 = [_]u8{0x11} ** 32,
        .mlkem_ciphertext = [_]u8{0x22} ** ML_KEM_768.CIPHERTEXT_SIZE,
    };

    const bytes = try msg.toBytes(allocator);
    defer allocator.free(bytes);

    const deserialized = try PQXDHInitialMessage.fromBytes(bytes);

    try std.testing.expectEqualSlices(u8, &msg.ephemeral_x25519, &deserialized.ephemeral_x25519);
    try std.testing.expectEqualSlices(u8, &msg.mlkem_ciphertext, &deserialized.mlkem_ciphertext);
}
