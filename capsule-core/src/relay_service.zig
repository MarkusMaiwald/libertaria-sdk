//! Relay Service - Layer 2 Packet Forwarding
//!
//! This service handles incoming relay packets, unwraps them,
//! and forwards them to the next hop in the circuit.

const std = @import("std");
const relay_mod = @import("relay");
const dht_mod = @import("dht");

pub const RelayService = struct {
    allocator: std.mem.Allocator,
    onion_builder: relay_mod.OnionBuilder,

    // Statistics
    packets_forwarded: u64,
    packets_dropped: u64,

    pub fn init(allocator: std.mem.Allocator) RelayService {
        return .{
            .allocator = allocator,
            .onion_builder = relay_mod.OnionBuilder.init(allocator),
            .packets_forwarded = 0,
            .packets_dropped = 0,
        };
    }

    pub fn deinit(self: *RelayService) void {
        _ = self;
    }

    /// Forward a relay packet to the next hop
    /// Returns the next hop address and the inner payload
    pub fn forwardPacket(
        self: *RelayService,
        packet: relay_mod.RelayPacket,
        shared_secret: [32]u8,
    ) !struct { next_hop: [32]u8, payload: []u8 } {
        // Unwrap the onion layer
        const result = try self.onion_builder.unwrapLayer(packet, shared_secret);

        // Check if next_hop is all zeros (meaning we're the final destination)
        const is_final = blk: {
            for (result.next_hop) |b| {
                if (b != 0) break :blk false;
            }
            break :blk true;
        };

        if (is_final) {
            // We're the final destination - deliver locally
            std.log.info("Relay: Final destination reached, delivering payload locally", .{});
            self.packets_dropped += 1; // Not actually dropped, just not forwarded
            return result;
        }

        // Forward to next hop
        std.log.debug("Relay: Forwarding to next hop: {x}", .{std.fmt.fmtSliceHexLower(&result.next_hop)});
        self.packets_forwarded += 1;

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
    const shared_secret = [_]u8{0} ** 32;

    var onion_builder = relay_mod.OnionBuilder.init(allocator);
    var packet = try onion_builder.wrapLayer(payload, next_hop, shared_secret);
    defer packet.deinit(allocator);

    // Forward the packet
    const result = try relay_service.forwardPacket(packet, shared_secret);
    defer allocator.free(result.payload);

    try std.testing.expectEqualSlices(u8, &next_hop, &result.next_hop);
    try std.testing.expectEqualSlices(u8, payload, result.payload);

    // Check stats
    const stats = relay_service.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.packets_forwarded);
}
