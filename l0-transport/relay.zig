//! RFC-0018: Relay Protocol (Layer 2)
//!
//! Implements onion-routed packet forwarding.
//!
//! Packet Structure (Conceptual Onion):
//! [ Next Hop: R1 | Encrypted Payload for R1 [ Next Hop: R2 | Encrypted Payload for R2 [ Target: B | Payload ] ] ]
//!
//! For Phase 13 (Week 34), we implement the packet framing and wrapping logic.
//! We assume shared secrets are established via the Federation Handshake (or Prekey bundles).

const std = @import("std");
const crypto = @import("std").crypto;
const net = std.net;

/// Fixed packet size to mitigate side-channel analysis (size correlation).
/// Real-world implementation might use 4KB or 1KB chunks.
pub const RELAY_PACKET_SIZE = 1024 + 128; // Payload + Headers

pub const RelayError = error{
    PacketTooLarge,
    DecryptionFailed,
    InvalidNextHop,
    HopLimitExceeded,
};

/// The routing header visible to the current relay after decryption.
pub const NextHopHeader = struct {
    next_hop_id: [32]u8, // NodeID (0x00... for exit/final destination)
    // We might add HMAC or integrity check here
};

/// A Relay Packet as it travels on the wire.
/// It effectively contains an encrypted blob that the receiver can decrypt
/// to reveal the NextHopHeader and the inner Payload.
pub const RelayPacket = struct {
    // Public ephemeral key for ECDH could be here if we do per-packet keying,
    // but typically we use established session keys or pre-keys.
    // For simplicity V1, we assume a session key exists or use a nonce.

    nonce: [24]u8, // XChaCha20 nonce
    ciphertext: []u8, // Encrypted [NextHopHeader + InnerPayload]

    pub fn init(allocator: std.mem.Allocator, size: usize) !RelayPacket {
        return RelayPacket{
            .nonce = undefined, // To be filled
            .ciphertext = try allocator.alloc(u8, size),
        };
    }

    pub fn deinit(self: *RelayPacket, allocator: std.mem.Allocator) void {
        allocator.free(self.ciphertext);
    }
};

/// Logic to construct an onion packet.
pub const OnionBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) OnionBuilder {
        return .{
            .allocator = allocator,
        };
    }

    /// Wraps a payload into a single layer of encryption for a specific relay.
    /// In a real onion, this is called iteratively from innermost to outermost.
    pub fn wrapLayer(
        self: *OnionBuilder,
        payload: []const u8,
        next_hop: [32]u8,
        shared_secret: [32]u8,
    ) !RelayPacket {
        _ = shared_secret;
        // 1. Construct Cleartext: [NextHop (32) | Payload (N)]
        var cleartext = try self.allocator.alloc(u8, 32 + payload.len);
        defer self.allocator.free(cleartext);

        @memcpy(cleartext[0..32], &next_hop);
        @memcpy(cleartext[32..], payload);

        // 2. Encrypt
        var packet = try RelayPacket.init(self.allocator, cleartext.len + 16); // +AuthTag
        crypto.random.bytes(&packet.nonce);

        // Mock Encryption (XChaCha20-Poly1305 would go here)
        // For MVP structure, we just copy (TODO: Add actual crypto integration)
        // We simulate "encryption" by XORing with a byte for testing proving modification works
        for (cleartext, 0..) |b, i| {
            packet.ciphertext[i] = b ^ 0xFF; // Simple NOT for mock encryption
        }
        // Mock Auth Tag
        @memset(packet.ciphertext[cleartext.len..], 0xAA);

        return packet;
    }

    /// Unwraps a single layer (Server/Relay side logic).
    pub fn unwrapLayer(
        self: *OnionBuilder,
        packet: RelayPacket,
        shared_secret: [32]u8,
    ) !struct { next_hop: [32]u8, payload: []u8 } {
        _ = shared_secret;

        // Mock Decryption
        if (packet.ciphertext.len < 32 + 16) return error.DecryptionFailed;

        const content_len = packet.ciphertext.len - 16;
        var cleartext = try self.allocator.alloc(u8, content_len);

        for (0..content_len) |i| {
            cleartext[i] = packet.ciphertext[i] ^ 0xFF;
        }

        var next_hop: [32]u8 = undefined;
        @memcpy(&next_hop, cleartext[0..32]);

        // Move payload to a new buffer to shrink
        const payload_len = content_len - 32;
        const payload = try self.allocator.alloc(u8, payload_len);
        @memcpy(payload, cleartext[32..]);

        self.allocator.free(cleartext);

        return .{
            .next_hop = next_hop,
            .payload = payload,
        };
    }
};

test "Relay: wrap and unwrap" {
    const allocator = std.testing.allocator;
    var builder = OnionBuilder.init(allocator);

    const payload = "Hello Onion!";
    const next_hop = [_]u8{0xAB} ** 32;
    const shared_secret = [_]u8{0} ** 32;

    var packet = try builder.wrapLayer(payload, next_hop, shared_secret);
    defer packet.deinit(allocator);

    // Verify it is "encrypted" (XOR 0xFF)
    // Payload "H" (0x48) ^ 0xFF = 0xB7
    // First byte of cleartext is next_hop[0] (0xAB) ^ 0xFF = 0x54
    try std.testing.expectEqual(@as(u8, 0x54), packet.ciphertext[0]);

    const result = try builder.unwrapLayer(packet, shared_secret);
    defer allocator.free(result.payload);

    try std.testing.expectEqualSlices(u8, &next_hop, &result.next_hop);
    try std.testing.expectEqualSlices(u8, payload, result.payload);
}
