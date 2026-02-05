//! Example: Encrypting and decrypting payloads
//!
//! This demonstrates basic usage of the L1 crypto layer.

const std = @import("std");
const crypto_mod = @import("../../core/l1-identity/crypto.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    std.debug.print("Libertaria SDK - Encryption Example\n", .{});
    std.debug.print("====================================\n\n", .{});

    // Generate keypairs
    var sender_private: [32]u8 = undefined;
    var recipient_private: [32]u8 = undefined;
    std.crypto.random.bytes(&sender_private);
    std.crypto.random.bytes(&recipient_private);

    const recipient_public = try std.crypto.dh.X25519.recoverPublicKey(recipient_private);

    std.debug.print("1. Generated keypairs:\n", .{});
    std.debug.print("   Sender private key: ", .{});
    for (sender_private[0..8]) |byte| {
        std.debug.print("{X:0>2}", .{byte});
    }
    std.debug.print("...\n", .{});
    std.debug.print("   Recipient public key: ", .{});
    for (recipient_public[0..8]) |byte| {
        std.debug.print("{X:0>2}", .{byte});
    }
    std.debug.print("...\n\n", .{});

    // Plaintext message
    const plaintext = "Hello, Libertaria! This is a secret message.";

    std.debug.print("2. Plaintext message:\n", .{});
    std.debug.print("   \"{s}\"\n", .{plaintext});
    std.debug.print("   Length: {} bytes\n\n", .{plaintext.len});

    // Encrypt
    var encrypted = try crypto_mod.encryptPayload(
        plaintext,
        recipient_public,
        sender_private,
        allocator,
    );
    defer encrypted.deinit(allocator);

    std.debug.print("3. Encrypted payload:\n", .{});
    std.debug.print("   Ephemeral pubkey: ", .{});
    for (encrypted.ephemeral_pubkey[0..8]) |byte| {
        std.debug.print("{X:0>2}", .{byte});
    }
    std.debug.print("...\n", .{});
    std.debug.print("   Nonce: ", .{});
    for (encrypted.nonce[0..8]) |byte| {
        std.debug.print("{X:0>2}", .{byte});
    }
    std.debug.print("...\n", .{});
    std.debug.print("   Ciphertext length: {} bytes (includes 16-byte auth tag)\n", .{encrypted.ciphertext.len});
    std.debug.print("   Total encrypted size: {} bytes\n\n", .{encrypted.size()});

    // Decrypt
    const decrypted = try crypto_mod.decryptPayload(&encrypted, recipient_private, allocator);
    defer allocator.free(decrypted);

    std.debug.print("4. Decrypted message:\n", .{});
    std.debug.print("   \"{s}\"\n", .{decrypted});
    std.debug.print("   Length: {} bytes\n\n", .{decrypted.len});

    // Verify
    const match = std.mem.eql(u8, plaintext, decrypted);
    std.debug.print("5. Verification:\n", .{});
    std.debug.print("   Plaintext matches decrypted: {}\n\n", .{match});

    if (match) {
        std.debug.print("✅ Encryption/decryption roundtrip works!\n\n", .{});
    } else {
        std.debug.print("❌ Decryption failed!\n\n", .{});
        return error.DecryptionMismatch;
    }

    // Demonstrate WORLD tier encryption
    std.debug.print("6. WORLD tier encryption (everyone can decrypt):\n\n", .{});

    const world_message = "Hello, World Feed!";
    std.debug.print("   Original: \"{s}\"\n", .{world_message});

    var world_encrypted = try crypto_mod.encryptWorld(world_message, sender_private, allocator);
    defer world_encrypted.deinit(allocator);

    std.debug.print("   Encrypted size: {} bytes\n", .{world_encrypted.size()});

    const world_decrypted = try crypto_mod.decryptWorld(&world_encrypted, recipient_private, allocator);
    defer allocator.free(world_decrypted);

    std.debug.print("   Decrypted: \"{s}\"\n", .{world_decrypted});
    std.debug.print("   Match: {}\n\n", .{std.mem.eql(u8, world_message, world_decrypted)});

    std.debug.print("✅ WORLD tier encryption works!\n", .{});
}
