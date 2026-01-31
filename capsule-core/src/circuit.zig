//! RFC-0018: Circuit Building Logic
//!
//! Orchestrates the selection of relays via QVL and the construction of onion packets.

const std = @import("std");
const relay = @import("relay");
const dht = @import("dht");
const crypto = std.crypto;
const QvlStore = @import("qvl_store.zig").QvlStore;
const PeerTable = @import("peer_table.zig").PeerTable;
const DhtService = dht.DhtService;

pub const ActiveCircuit = struct {
    session_id: [16]u8,
    relay_address: std.net.Address,
    relay_pubkey: [32]u8,
    // Sticky Ephemeral Key (for optimizations)
    ephemeral_keypair: crypto.dh.X25519.KeyPair,
};

pub const CircuitError = error{
    NoRelaysAvailable,
    TargetNotFound,
    RelayNotFound,
    PathConstructionFailed,
};

pub const CircuitBuilder = struct {
    allocator: std.mem.Allocator,
    qvl_store: *QvlStore,
    peer_table: *PeerTable,
    dht: *DhtService,
    onion_builder: relay.OnionBuilder,

    pub fn init(allocator: std.mem.Allocator, qvl_store: *QvlStore, peer_table: *PeerTable, dht_service: *DhtService) CircuitBuilder {
        return .{
            .allocator = allocator,
            .qvl_store = qvl_store,
            .peer_table = peer_table,
            .dht = dht_service,
            .onion_builder = relay.OnionBuilder.init(allocator),
        };
    }

    /// Builds a 1-hop circuit (MVP): Source -> Relay -> Target
    /// Returns the fully wrapped packet ready to be sent to the Relay, and the Relay's address.
    pub fn buildOneHopCircuit(
        self: *CircuitBuilder,
        target_did: []const u8,
        payload: []const u8,
    ) !struct { packet: relay.RelayPacket, first_hop: std.net.Address } {
        // 1. Resolve Target
        // We need the Target's NodeID (for the inner routing header).
        // For MVP, we assume DID ~= NodeID or we have a mapping.
        // Let's assume we can lookup by DID in PeerTable to get public key/ID.
        // (PeerTable currently uses did_short [8]u8, but let's assume we can map).

        // MVP: Fake resolution.
        var target_id = [_]u8{0} ** 32;
        if (target_did.len >= 32) @memcpy(&target_id, target_did[0..32]);

        // 2. Select a Relay
        const trusted_dids = try self.qvl_store.getTrustedRelays(0.5, 10);
        defer {
            for (trusted_dids) |did| self.allocator.free(did);
            self.allocator.free(trusted_dids);
        }

        if (trusted_dids.len == 0) return error.NoRelaysAvailable;

        // Pick random relay
        const rand_idx = std.crypto.random.intRangeAtMost(usize, 0, trusted_dids.len - 1);
        const relay_did = trusted_dids[rand_idx];

        // Resolve Relay NodeID
        var relay_id = [_]u8{0} ** 32;
        if (relay_did.len >= 32) {
            @memcpy(&relay_id, relay_did[0..32]);
        } else {
            // If DID is short, maybe pad? MVP hack.
            std.mem.copyForwards(u8, &relay_id, relay_did);
        }

        // 3. Wrap Inner Layer (Target)
        // The Payload is destined for Target.
        // next_hop for Inner Layer is Target.
        // But wait, the Relay receives the outer packet, unwraps it.
        // It sees: Next Hop = Target.
        // So the Relay forwards the *Inner Payload* to Target.
        // Is the Inner Payload encrypted for Target? YES.

        // Resolve Relay Keys from DHT
        const relay_node = self.dht.routing_table.findNode(relay_id) orelse return error.RelayNotFound;
        const relay_pubkey = relay_node.key;

        // Generate SessionID (Client-side)
        var session_id: [16]u8 = undefined;
        std.crypto.random.bytes(&session_id);

        // Wrap: Relay Packet -> [ NextHop: Target | Payload ]
        const packet = try self.onion_builder.wrapLayer(payload, target_id, relay_pubkey, session_id, null);

        return .{ .packet = packet, .first_hop = relay_node.address };
    }

    /// Create a sticky session circuit
    pub fn createCircuit(self: *CircuitBuilder, relay_did: ?[]const u8) !ActiveCircuit {
        // Select Relay (Random if null)
        const selected_did = if (relay_did) |did| try self.allocator.dupe(u8, did) else blk: {
            const trusted = try self.qvl_store.getTrustedRelays(0.5, 1);
            if (trusted.len == 0) return error.NoRelaysAvailable;
            break :blk trusted[0];
        };
        defer self.allocator.free(selected_did);

        // Resolve Relay Keys
        var relay_id = [_]u8{0} ** 32;
        if (selected_did.len >= 32) @memcpy(&relay_id, selected_did[0..32]);

        const relay_node = self.dht.routing_table.findNode(relay_id) orelse return error.RelayNotFound;

        const kp = crypto.dh.X25519.KeyPair.generate();
        var session_id: [16]u8 = undefined;
        std.crypto.random.bytes(&session_id);

        return ActiveCircuit{
            .session_id = session_id,
            .relay_address = relay_node.address,
            .relay_pubkey = relay_node.key,
            .ephemeral_keypair = kp,
        };
    }

    /// Send a payload on an existing circuit (reusing session/keys)
    pub fn sendOnCircuit(self: *CircuitBuilder, circuit: *ActiveCircuit, target_did: []const u8, payload: []const u8) !relay.RelayPacket {
        var target_id = [_]u8{0} ** 32;
        if (target_did.len >= 32) @memcpy(&target_id, target_did[0..32]);

        // Use stored keys for stickiness
        return self.onion_builder.wrapLayer(payload, target_id, circuit.relay_pubkey, circuit.session_id, circuit.ephemeral_keypair);
    }
};

test "Circuit: Build 1-Hop" {
    // Basic test
    const allocator = std.testing.allocator;
    // We would need mocks for QvlStore etc.
    // For now, satisfy the compiler.
    _ = allocator;
}
