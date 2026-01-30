// Test file for PQXDH protocol (RFC-0830)
// Located at: l1-identity/test_pqxdh.zig
//
// This file tests the PQXDH key agreement ceremony with stubbed ML-KEM functions.
// Once liboqs is built, these tests will use real ML-KEM-768 implementation.

const std = @import("std");
const pqxdh = @import("pqxdh.zig");
const testing = std.testing;

// ============================================================================
// STUB: ML-KEM-768 Functions (for testing without liboqs)
// ============================================================================
// These will be replaced with real liboqs FFI once library is built

export fn OQS_KEM_kyber768_keypair(
    public_key: ?*u8,
    secret_key: ?*u8,
) c_int {
    // Stub: Fill with deterministic test data
    if (public_key) |pk| {
        const pk_slice: [*]u8 = @ptrCast(pk);
        @memset(pk_slice[0..pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE], 0xAA);
    }
    if (secret_key) |sk| {
        const sk_slice: [*]u8 = @ptrCast(sk);
        @memset(sk_slice[0..pqxdh.ML_KEM_768.SECRET_KEY_SIZE], 0xBB);
    }
    return 0; // Success
}

export fn OQS_KEM_kyber768_encaps(
    ciphertext: ?*u8,
    shared_secret: ?*u8,
    public_key: ?*const u8,
) c_int {
    _ = public_key; // Use in real impl

    // Stub: Generate deterministic shared secret + ciphertext
    if (ciphertext) |ct| {
        const ct_slice: [*]u8 = @ptrCast(ct);
        @memset(ct_slice[0..pqxdh.ML_KEM_768.CIPHERTEXT_SIZE], 0xCC);
    }
    if (shared_secret) |ss| {
        const ss_slice: [*]u8 = @ptrCast(ss);
        @memset(ss_slice[0..pqxdh.ML_KEM_768.SHARED_SECRET_SIZE], 0xDD);
    }
    return 0; // Success
}

export fn OQS_KEM_kyber768_decaps(
    shared_secret: ?*u8,
    ciphertext: ?*const u8,
    secret_key: ?*const u8,
) c_int {
    _ = ciphertext; // Use in real impl
    _ = secret_key; // Use in real impl

    // Stub: Must return SAME shared secret as encaps for protocol to work
    if (shared_secret) |ss| {
        const ss_slice: [*]u8 = @ptrCast(ss);
        @memset(ss_slice[0..pqxdh.ML_KEM_768.SHARED_SECRET_SIZE], 0xDD);
    }
    return 0; // Success
}

// ============================================================================
// Helper: Generate Test Keypairs
// ============================================================================

fn generateTestKeypair() ![32]u8 {
    var private_key: [32]u8 = undefined;
    std.crypto.random.bytes(&private_key);
    return private_key;
}

// ============================================================================
// Tests
// ============================================================================

test "PQXDHPrekeyBundle serialization roundtrip" {
    const allocator = testing.allocator;

    var bundle = pqxdh.PrekeyBundle{
        .identity_key = [_]u8{0x01} ** 32,
        .signed_prekey_x25519 = [_]u8{0x02} ** 32,
        .signed_prekey_signature = [_]u8{0x03} ** 64,
        .signed_prekey_mlkem = [_]u8{0x04} ** pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE,
        .one_time_prekey_x25519 = [_]u8{0x05} ** 32,
        .one_time_prekey_mlkem = [_]u8{0x06} ** pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE,
    };

    // Serialize
    const bytes = try bundle.toBytes(allocator);
    defer allocator.free(bytes);

    // Expected size: 32 + 32 + 64 + 1184 + 32 + 1184 = 2528 bytes
    try testing.expectEqual(@as(usize, 2528), bytes.len);

    // Deserialize
    const restored = try pqxdh.PrekeyBundle.fromBytes(allocator, bytes);

    // Verify all fields match
    try testing.expectEqualSlices(u8, &bundle.identity_key, &restored.identity_key);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_x25519, &restored.signed_prekey_x25519);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_signature, &restored.signed_prekey_signature);
    try testing.expectEqualSlices(u8, &bundle.signed_prekey_mlkem, &restored.signed_prekey_mlkem);
    try testing.expectEqualSlices(u8, &bundle.one_time_prekey_x25519, &restored.one_time_prekey_x25519);
    try testing.expectEqualSlices(u8, &bundle.one_time_prekey_mlkem, &restored.one_time_prekey_mlkem);
}

test "PQXDHInitialMessage serialization roundtrip" {
    const allocator = testing.allocator;

    var msg = pqxdh.PQXDHInitialMessage{
        .ephemeral_x25519 = [_]u8{0x11} ** 32,
        .mlkem_ciphertext = [_]u8{0x22} ** pqxdh.ML_KEM_768.CIPHERTEXT_SIZE,
    };

    // Serialize
    const bytes = try msg.toBytes(allocator);
    defer allocator.free(bytes);

    // Expected size: 32 + 1088 = 1120 bytes
    try testing.expectEqual(@as(usize, 1120), bytes.len);

    // Deserialize
    const restored = try pqxdh.PQXDHInitialMessage.fromBytes(bytes);

    // Verify fields match
    try testing.expectEqualSlices(u8, &msg.ephemeral_x25519, &restored.ephemeral_x25519);
    try testing.expectEqualSlices(u8, &msg.mlkem_ciphertext, &restored.mlkem_ciphertext);
}

test "PQXDH full handshake roundtrip (stubbed ML-KEM)" {
    const allocator = testing.allocator;

    // === Bob's Setup ===
    // Generate Bob's long-term identity key (Ed25519 → X25519 conversion)
    const bob_identity_private = try generateTestKeypair();
    const bob_identity_public = try std.crypto.dh.X25519.recoverPublicKey(bob_identity_private);

    // Generate Bob's signed prekey (X25519)
    const bob_signed_prekey_private = try generateTestKeypair();
    const bob_signed_prekey_public = try std.crypto.dh.X25519.recoverPublicKey(bob_signed_prekey_private);

    // Generate Bob's one-time prekey (X25519)
    const bob_onetime_prekey_private = try generateTestKeypair();
    const bob_onetime_prekey_public = try std.crypto.dh.X25519.recoverPublicKey(bob_onetime_prekey_private);

    // Generate Bob's ML-KEM keypair (stubbed)
    var bob_mlkem_public: [pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8 = undefined;
    var bob_mlkem_private: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8 = undefined;
    const kem_result = OQS_KEM_kyber768_keypair(&bob_mlkem_public[0], &bob_mlkem_private[0]);
    try testing.expectEqual(@as(c_int, 0), kem_result);

    // Create Bob's prekey bundle (signature stubbed for now)
    var bob_bundle = pqxdh.PrekeyBundle{
        .identity_key = bob_identity_public,
        .signed_prekey_x25519 = bob_signed_prekey_public,
        .signed_prekey_signature = [_]u8{0} ** 64, // TODO: Real Ed25519 signature
        .signed_prekey_mlkem = bob_mlkem_public,
        .one_time_prekey_x25519 = bob_onetime_prekey_public,
        .one_time_prekey_mlkem = bob_mlkem_public, // Reuse for test
    };

    // === Alice's Setup ===
    const alice_identity_private = try generateTestKeypair();
    const alice_identity_public = try std.crypto.dh.X25519.recoverPublicKey(alice_identity_private);

    // === Alice Initiates Handshake ===
    const alice_result = try pqxdh.initiator(
        alice_identity_private,
        &bob_bundle,
        allocator,
    );

    // Verify Alice got a root key
    var alice_has_nonzero = false;
    for (alice_result.root_key) |byte| {
        if (byte != 0) {
            alice_has_nonzero = true;
            break;
        }
    }
    try testing.expect(alice_has_nonzero);

    // === Bob Responds to Handshake ===
    const bob_result = try pqxdh.responder(
        bob_identity_private,
        bob_signed_prekey_private,
        bob_onetime_prekey_private,
        bob_mlkem_private,
        alice_identity_public,
        &alice_result.initial_message,
    );

    // === Verify Root Keys Match ===
    // This is the critical test: both parties must derive the SAME root key
    try testing.expectEqualSlices(u8, &alice_result.root_key, &bob_result.root_key);

    std.debug.print("\n✅ PQXDH Handshake: Alice and Bob derived matching root keys!\n", .{});
    std.debug.print("   Root key (first 16 bytes): {x}\n", .{alice_result.root_key[0..16]});
}

test "PQXDH error: invalid ML-KEM encapsulation" {
    // Test that errors propagate correctly when ML-KEM fails
    // (This test will be more meaningful with real liboqs)

    // For now, just verify our stub functions return success
    var public_key: [pqxdh.ML_KEM_768.PUBLIC_KEY_SIZE]u8 = undefined;
    var secret_key: [pqxdh.ML_KEM_768.SECRET_KEY_SIZE]u8 = undefined;

    const result = OQS_KEM_kyber768_keypair(&public_key[0], &secret_key[0]);
    try testing.expectEqual(@as(c_int, 0), result);
}
