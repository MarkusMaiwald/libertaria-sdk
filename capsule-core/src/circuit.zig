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

pub const CircuitHop = struct {
    relay_id: [32]u8,
    relay_pubkey: [32]u8,
    session_id: [16]u8,
    ephemeral_keypair: crypto.dh.X25519.KeyPair,
};

pub const ActiveCircuit = struct {
    path: std.ArrayList(CircuitHop),
    target_id: [32]u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ActiveCircuit) void {
        self.path.deinit();
    }
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

    /// Build a multi-hop circuit to a specific target
    /// Hops must be resolved NodeIDs [Relay1, Relay2, Relay3]
    /// Packet flows: Me -> Relay1 -> Relay2 -> Relay3 -> Target
    pub fn buildCircuit(
        self: *CircuitBuilder,
        hops: []const [32]u8,
    ) !ActiveCircuit {
        var circuit = ActiveCircuit{
            .path = std.ArrayList(CircuitHop).init(self.allocator),
            .target_id = [_]u8{0} ** 32, // Set later or unused for pure circuit
            .allocator = self.allocator,
        };
        errdefer circuit.deinit();

        for (hops) |node_id| {
            // Resolve Relay Keys
            const node = self.dht.routing_table.findNode(node_id) orelse return error.RelayNotFound;

            // Generate Session & Keys
            const kp = crypto.dh.X25519.KeyPair.generate();
            var session_id: [16]u8 = undefined;
            std.crypto.random.bytes(&session_id);

            try circuit.path.append(CircuitHop{
                .relay_id = node_id,
                .relay_pubkey = node.key,
                .session_id = session_id,
                .ephemeral_keypair = kp,
            });
        }
        return circuit;
    }

    /// Send payload through the circuit
    /// Recursively wraps the onion: Target <- H3 <- H2 <- H1 <- Me
    pub fn sendOnCircuit(
        self: *CircuitBuilder,
        circuit: *ActiveCircuit,
        target_id: [32]u8,
        payload: []const u8,
    ) !relay.RelayPacket {
        // 1. Start with the payload destined for Target
        // The last hop (Exit Node) sees: NextHop = Target.
        // We wrap from inside out.

        // We need to construct the chain of packets.
        // But `wrapLayer` produces a `RelayPacket` struct, which contains `payload`.
        // To wrap again, we must ENCODE the inner packet to bytes, then wrap that as payload.

        // Step A: Wrap for final destination
        // The Exit Node (last hop) sends to Target.
        // Exit Node uses `circuit.path.last`.
        if (circuit.path.items.len == 0) return error.PathConstructionFailed;

        const exit_hop = circuit.path.items[circuit.path.items.len - 1];

        // Inner: Exit -> Target
        var current_packet = try self.onion_builder.wrapLayer(payload, target_id, exit_hop.relay_pubkey, exit_hop.session_id, exit_hop.ephemeral_keypair);

        // Step B: Wrap backwards
        var i: usize = circuit.path.items.len - 1;
        while (i > 0) : (i -= 1) {
            const inner_hop = circuit.path.items[i]; // The one we just wrapped for
            const outer_hop = circuit.path.items[i - 1]; // The one who sends to inner_hop

            // Encode current packet to be payload for next layer
            const inner_bytes = try current_packet.encode(self.allocator);
            // Free the struct, we have bytes
            current_packet.deinit(self.allocator);
            defer self.allocator.free(inner_bytes);

            // Wrap: Outer -> Inner
            current_packet = try self.onion_builder.wrapLayer(inner_bytes, inner_hop.relay_id, outer_hop.relay_pubkey, outer_hop.session_id, outer_hop.ephemeral_keypair);
        }

        return current_packet;
    }
};

test "Circuit: Build 1-Hop" {
    // Basic test
    const allocator = std.testing.allocator;
    // We would need mocks for QvlStore etc.
    // For now, satisfy the compiler.
    _ = allocator;
}
