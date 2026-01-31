//! RFC-0120 S5.2: Peer Table
//! Manages a list of known nodes on the network and their health/trust metrics.

const std = @import("std");
const net = std.net;

pub const Peer = struct {
    address: net.Address,
    did_short: [8]u8, // Short hash of DID (RFC-0120 S4.1)
    last_seen: i64,
    trust_score: f32 = 1.0,
    is_active: bool = true,
};

pub const PeerTable = struct {
    allocator: std.mem.Allocator,
    peers: std.AutoHashMap([8]u8, Peer),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) PeerTable {
        return PeerTable{
            .allocator = allocator,
            .peers = std.AutoHashMap([8]u8, Peer).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *PeerTable) void {
        self.peers.deinit();
    }

    /// Update or add a peer to the table
    pub fn updatePeer(self: *PeerTable, did_short: [8]u8, address: net.Address) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        if (self.peers.getPtr(did_short)) |peer| {
            peer.address = address;
            peer.last_seen = now;
            peer.is_active = true;
        } else {
            try self.peers.put(did_short, Peer{
                .address = address,
                .did_short = did_short,
                .last_seen = now,
            });
            std.log.info("Discovered new peer: {x} at {f}", .{ did_short, address });
        }
    }

    /// Mark peers as inactive if not seen for a while (Decay)
    pub fn tick(self: *PeerTable) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.timestamp();
        const timeout = 300; // 5 minutes

        var it = self.peers.iterator();
        while (it.next()) |entry| {
            if (now - entry.value_ptr.last_seen > timeout) {
                if (entry.value_ptr.is_active) {
                    entry.value_ptr.is_active = false;
                    std.log.debug("Peer timed out: {x}", .{entry.key_ptr.*});
                }
            }
        }
    }
};
