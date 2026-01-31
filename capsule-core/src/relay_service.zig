//! Relay Service - Layer 2 Packet Forwarding
//!
//! This service handles incoming relay packets, unwraps them,
//! and forwards them to the next hop in the circuit.

const std = @import("std");
const relay_mod = @import("relay");
const dht_mod = @import("dht");

pub const RelayService = struct {
    pub const SessionContext = struct {
        packet_count: u64,
        last_seen: i64,
    };

    allocator: std.mem.Allocator,
    onion_builder: relay_mod.OnionBuilder,

    // Statistics
    packets_forwarded: u64,
    packets_dropped: u64,
    sessions: std.AutoHashMap([16]u8, SessionContext),

    pub fn init(allocator: std.mem.Allocator) RelayService {
        return .{
            .allocator = allocator,
            .onion_builder = relay_mod.OnionBuilder.init(allocator),
            .packets_forwarded = 0,
            .packets_dropped = 0,
            .sessions = std.AutoHashMap([16]u8, SessionContext).init(allocator),
        };
    }

    pub fn deinit(self: *RelayService) void {
        self.sessions.deinit();
    }

    /// Forward a relay packet to the next hop
    /// Returns the next hop address and the inner payload
    /// Forward a relay packet to the next hop
    /// Returns the next hop address and the inner payload
    pub fn forwardPacket(
        self: *RelayService,
        raw_packet: []const u8,
        receiver_private_key: [32]u8,
    ) !struct { next_hop: [32]u8, payload: []u8, session_id: [16]u8 } {
        // Parse the wire packet
        var packet = try relay_mod.RelayPacket.decode(self.allocator, raw_packet);
        defer packet.deinit(self.allocator);

        // Unwrap the onion layer (using our private key + packet's ephemeral key)
        const result = try self.onion_builder.unwrapLayer(packet, receiver_private_key, null);

        // Check if next_hop is all zeros (meaning we're the final destination)
        const is_final = blk: {
            for (result.next_hop) |b| {
                if (b != 0) break :blk false;
            }
            break :blk true;
        };

        if (is_final) {
            // We're the final destination - deliver locally
            std.log.info("Relay: Final destination reached for session {x}", .{result.session_id});
            self.packets_dropped += 1; // Not actually dropped, just not forwarded
            return result;
        }

        // Forward to next hop
        std.log.debug("Relay: Forwarding session {x} to next hop: {x}", .{ result.session_id, std.fmt.fmtSliceHexLower(&result.next_hop) });

        // Update Sticky Session Stats
        const now = std.time.timestamp();
        const gop = try self.sessions.getOrPut(result.session_id);
        if (!gop.found_existing) {
            gop.value_ptr.* = .{ .packet_count = 1, .last_seen = now };
            std.log.info("Relay: New Sticky Session detected: {x}", .{result.session_id});
        } else {
            gop.value_ptr.packet_count += 1;
            gop.value_ptr.last_seen = now;
        }

        self.packets_forwarded += 1;

        // Result payload includes the re-wrapped inner onion?
        // Wait, unwrapLayer returns the decrypted payload.
        // In onion routing, the decrypted payload IS the inner onion for the next hop.
        // We just return it. The caller (node.zig) must send it.
        return result;
    }

    /// Get relay statistics
    pub fn getStats(self: *const RelayService) RelayStats {
        return .{
            .packets_forwarded = self.packets_forwarded,
            .packets_dropped = self.packets_dropped,
        };
    }
};

pub const RelayStats = struct {
    packets_forwarded: u64,
    packets_dropped: u64,
};

test "RelayService: Forward packet" {
    const allocator = std.testing.allocator;

    var relay_service = RelayService.init(allocator);
    defer relay_service.deinit();

    // Create a test packet
    const payload = "Test payload";
    const next_hop = [_]u8{0xAB} ** 32;
    // const shared_secret = [_]u8{0} ** 32; // Not used directly anymore, using private key

    // Generate keys
    const receiver_kp = std.crypto.dh.X25519.KeyPair.generate();
    const receiver_pub = receiver_kp.public_key;
    const receiver_priv = receiver_kp.secret_key;

    const session_id = [_]u8{0x11} ** 16;

    var onion_builder = relay_mod.OnionBuilder.init(allocator);
    // Wrap layer targeting the receiver
    var packet = try onion_builder.wrapLayer(payload, next_hop, receiver_pub, session_id, null);
    defer packet.deinit(allocator);

    const encoded = try packet.encode(allocator);
    defer allocator.free(encoded);

    // Forward the packet (pass encoded bytes)
    const result = try relay_service.forwardPacket(encoded, receiver_priv);
    defer allocator.free(result.payload);

    try std.testing.expectEqualSlices(u8, &next_hop, &result.next_hop);
    try std.testing.expectEqualSlices(u8, payload, result.payload);
    try std.testing.expectEqualSlices(u8, &session_id, &result.session_id);

    // Check stats
    const stats = relay_service.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.packets_forwarded);
}
