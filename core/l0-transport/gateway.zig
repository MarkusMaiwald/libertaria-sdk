// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Libertaria Contributors
// This file is part of the Libertaria Core, licensed under
// The Libertaria Commonwealth License v1.0.


//! RFC-0018: Gateway Protocol
//!
//! layer 1: Coordination Layer
//! Handles NAT hole punching, peer discovery, and relay announcements.
//! Gateways do NOT forward data traffic.

const std = @import("std");
const dht = @import("dht.zig");

// Placeholder type for NodeId when DHT is unavailable
const NodeId = [32]u8;

pub const Gateway = struct {
    allocator: std.mem.Allocator,
    dht: *dht.DhtService,

    // In-memory address registry (PeerID -> Public Address)
    peer_addresses: std.AutoHashMap(NodeId, std.net.Address),

    pub fn init(allocator: std.mem.Allocator, dht_service: *dht.DhtService) Gateway {
        return Gateway{
            .allocator = allocator,
            .dht = dht_service,
            .peer_addresses = std.AutoHashMap(NodeId, std.net.Address).init(allocator),
        };
    }

    pub fn deinit(self: *Gateway) void {
        self.peer_addresses.deinit();
    }

    /// Register a peer's public address
    pub fn registerPeer(self: *Gateway, peer_id: NodeId, addr: std.net.Address) !void {
        try self.peer_addresses.put(peer_id, addr);
    }

    /// STUN-like coordination for hole punching
    pub fn coordinateHolePunch(
        self: *Gateway,
        peer_a: NodeId,
        peer_b: NodeId,
    ) !HolePunchCoordination {
        const addr_a = self.peer_addresses.get(peer_a) orelse return error.PeerNotFound;
        const addr_b = self.peer_addresses.get(peer_b) orelse return error.PeerNotFound;

        return HolePunchCoordination{
            .peer_a_addr = addr_a,
            .peer_b_addr = addr_b,
            .timestamp = @intCast(std.time.timestamp()),
        };
    }
};

pub const HolePunchCoordination = struct {
    peer_a_addr: std.net.Address,
    peer_b_addr: std.net.Address,
    timestamp: u64,
};

test "Gateway: register and coordinate" {
    const allocator = std.testing.allocator;

    // Create a mock DHT service for testing
    var self_id = [_]u8{0} ** 32;
    self_id[0] = 0xAB;
    var dht_service = dht.DhtService.init(allocator, self_id);
    defer dht_service.deinit();

    var gw = Gateway.init(allocator, &dht_service);
    defer gw.deinit();

    var peer_a_id = [_]u8{0} ** 32;
    peer_a_id[0] = 0xAA;
    var peer_b_id = [_]u8{0} ** 32;
    peer_b_id[0] = 0xBB;

    const addr_a = try std.net.Address.parseIp("1.2.3.4", 8080);
    const addr_b = try std.net.Address.parseIp("5.6.7.8", 9090);

    try gw.registerPeer(peer_a_id, addr_a);
    try gw.registerPeer(peer_b_id, addr_b);

    const coord = try gw.coordinateHolePunch(peer_a_id, peer_b_id);

    try std.testing.expect(coord.peer_a_addr.eql(addr_a));
    try std.testing.expect(coord.peer_b_addr.eql(addr_b));
}
