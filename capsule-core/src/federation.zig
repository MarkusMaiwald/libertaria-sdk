//! RFC-0120 S6: Federation Handshake
//! Handshake protocol for establishing identity and trust between Capsules.

const std = @import("std");
const net = std.net;
const l0_transport = @import("l0_transport");
const lwf = l0_transport.lwf;

pub const VERSION: u32 = 2;
pub const SERVICE_TYPE: u16 = lwf.LWFHeader.ServiceType.IDENTITY_SIGNAL;

pub const DhtNode = struct {
    id: [32]u8,
    address: net.Address,
    key: [32]u8,
};

pub const SessionState = enum {
    Connecting, // Discovered, TCP/UTCP handshake in progress
    Authenticating, // Exchange DIDs and signatures
    Federated, // Ready for mesh operations
    Disconnected,
};

pub const FederationMessage = union(enum) {
    hello: struct {
        did_short: [8]u8,
        version: u32,
    },
    welcome: struct {
        did_short: [8]u8,
    },
    auth: struct {
        signature: [64]u8, // Signature over nonce
    },
    // DHT RPCs (ServiceType: IDENTITY_SIGNAL)
    dht_ping: struct {
        node_id: [32]u8,
    },
    dht_pong: struct {
        node_id: [32]u8,
    },
    dht_find_node: struct {
        target_id: [32]u8,
    },
    dht_nodes: struct {
        nodes: []const DhtNode,
    },
    // Gateway Coordination
    hole_punch_request: struct {
        target_id: [32]u8,
    },
    hole_punch_notify: struct {
        peer_id: [32]u8,
        address: net.Address,
    },

    pub fn encode(self: FederationMessage, writer: anytype) !void {
        try writer.writeByte(@intFromEnum(self));
        switch (self) {
            .hello => |h| {
                try writer.writeAll(&h.did_short);
                try writer.writeInt(u32, h.version, .big);
            },
            .welcome => |w| {
                try writer.writeAll(&w.did_short);
            },
            .auth => |a| {
                try writer.writeAll(&a.signature);
            },
            .dht_ping => |p| {
                try writer.writeAll(&p.node_id);
            },
            .dht_pong => |p| {
                try writer.writeAll(&p.node_id);
            },
            .dht_find_node => |f| {
                try writer.writeAll(&f.target_id);
            },
            .dht_nodes => |n| {
                try writer.writeInt(u16, @intCast(n.nodes.len), .big);
                for (n.nodes) |node| {
                    try writer.writeAll(&node.id);
                    try writer.writeAll(&node.key);
                    // For now we only support IPv4 in DHT nodes responses
                    if (node.address.any.family == std.posix.AF.INET) {
                        try writer.writeAll(&std.mem.toBytes(node.address.in.sa.addr));
                        try writer.writeInt(u16, node.address.getPort(), .big);
                    } else {
                        return error.UnsupportedAddressFamily;
                    }
                }
            },
            .hole_punch_request => |r| {
                try writer.writeAll(&r.target_id);
            },
            .hole_punch_notify => |n| {
                try writer.writeAll(&n.peer_id);
                // Serialize address (IPv4 only for now)
                if (n.address.any.family == std.posix.AF.INET) {
                    try writer.writeAll(&std.mem.toBytes(n.address.in.sa.addr));
                    try writer.writeInt(u16, n.address.getPort(), .big);
                } else {
                    return error.UnsupportedAddressFamily;
                }
            },
        }
    }

    pub fn decode(reader: anytype, allocator: std.mem.Allocator) !FederationMessage {
        const tag = try reader.readByte();
        return switch (@as(std.meta.Tag(FederationMessage), @enumFromInt(tag))) {
            .hello => .{
                .hello = .{
                    .did_short = try reader.readBytesNoEof(8),
                    .version = try reader.readInt(u32, .big),
                },
            },
            .welcome => .{
                .welcome = .{
                    .did_short = try reader.readBytesNoEof(8),
                },
            },
            .auth => .{
                .auth = .{
                    .signature = try reader.readBytesNoEof(64),
                },
            },
            .dht_ping => .{
                .dht_ping = .{
                    .node_id = try reader.readBytesNoEof(32),
                },
            },
            .dht_pong => .{
                .dht_pong = .{
                    .node_id = try reader.readBytesNoEof(32),
                },
            },
            .dht_find_node => .{
                .dht_find_node = .{
                    .target_id = try reader.readBytesNoEof(32),
                },
            },
            .dht_nodes => {
                const count = try reader.readInt(u16, .big);
                const nodes = try allocator.alloc(DhtNode, count);
                for (0..count) |i| {
                    const id = try reader.readBytesNoEof(32);
                    const key = try reader.readBytesNoEof(32);
                    const addr_u32 = try reader.readInt(u32, @import("builtin").target.cpu.arch.endian());
                    const port = try reader.readInt(u16, .big);
                    nodes[i] = .{
                        .id = id,
                        .address = net.Address.initIp4(std.mem.toBytes(addr_u32), port),
                        .key = key,
                    };
                }
                return .{ .dht_nodes = .{ .nodes = nodes } };
            },
            .hole_punch_request => .{
                .hole_punch_request = .{
                    .target_id = try reader.readBytesNoEof(32),
                },
            },
            .hole_punch_notify => {
                const id = try reader.readBytesNoEof(32);
                const addr_u32 = try reader.readInt(u32, @import("builtin").target.cpu.arch.endian());
                const port = try reader.readInt(u16, .big);
                return .{
                    .hole_punch_notify = .{
                        .peer_id = id,
                        .address = net.Address.initIp4(std.mem.toBytes(addr_u32), port),
                    },
                };
            },
        };
    }
};

pub const PeerSession = struct {
    address: net.Address,
    state: SessionState = .Connecting,
    did_short: [8]u8,

    pub fn init(address: net.Address, did_short: [8]u8) PeerSession {
        return .{
            .address = address,
            .did_short = did_short,
        };
    }
};
