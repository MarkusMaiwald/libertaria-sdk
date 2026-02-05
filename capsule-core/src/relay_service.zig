//! Relay Service - Layer 2 Packet Forwarding
//!
//! This service handles incoming relay packets, unwraps them,
//! and forwards them to the next hop in the circuit.

const std = @import("std");
const l0_transport = @import("l0_transport");
const relay_mod = l0_transport.relay;
const dht_mod = l0_transport.dht;

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
    ) !relay_mod.RelayResult {
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
        std.log.debug("Relay: Forwarding session {x} to next hop: {x}", .{ result.session_id, result.next_hop });

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

    /// Prune inactive sessions (Garbage Collection)
    /// Removes sessions inactive for more than max_age_seconds
    /// Returns number of sessions removed
    pub fn pruneSessions(self: *RelayService, max_age_seconds: u64) !usize {
        const now = std.time.timestamp();
        var expired_keys = std.ArrayList([16]u8).init(self.allocator);
        defer expired_keys.deinit();

        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            const age = now - entry.value_ptr.last_seen;
            if (age > @as(i64, @intCast(max_age_seconds))) {
                try expired_keys.append(entry.key_ptr.*);
            }
        }

        for (expired_keys.items) |key| {
            _ = self.sessions.remove(key);
        }

        return expired_keys.items.len;
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

test "RelayService: Session cleanup" {
    const allocator = std.testing.allocator;
    var service = RelayService.init(allocator);
    defer service.deinit();

    const session_id = [_]u8{0xAA} ** 16;
    const now = std.time.timestamp();

    // Add old session (2 hours ago)
    try service.sessions.put(session_id, .{
        .packet_count = 10,
        .last_seen = now - 7200,
    });

    // Add fresh session (10 seconds ago)
    const fresh_id = [_]u8{0xBB} ** 16;
    try service.sessions.put(fresh_id, .{
        .packet_count = 5,
        .last_seen = now - 10,
    });

    const removed = try service.pruneSessions(3600); // 1 hour max age
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expect(service.sessions.get(session_id) == null);
    try std.testing.expect(service.sessions.get(fresh_id) != null);
}
