//! RFC-0120 S5.1: Local Peer Discovery via mDNS
//! Implements a minimal mDNS advertiser and querier for _libertaria._udp.local

const std = @import("std");
const posix = std.posix;
const net = std.net;

pub const ip_mreq = extern struct {
    imr_multiaddr: u32,
    imr_interface: u32,
};

pub const DiscoveryService = struct {
    allocator: std.mem.Allocator,
    fd: posix.socket_t,
    port: u16,

    pub const MULTICAST_ADDR = "224.0.0.251";
    pub const MULTICAST_PORT = 5353;

    pub fn init(allocator: std.mem.Allocator, local_port: u16) !DiscoveryService {
        // 1. Create UDP socket
        const fd = try posix.socket(
            posix.AF.INET,
            posix.SOCK.DGRAM | posix.SOCK.CLOEXEC | posix.SOCK.NONBLOCK,
            posix.IPPROTO.UDP,
        );
        errdefer posix.close(fd);

        // 2. Allow port reuse (standard for mDNS)
        try posix.setsockopt(fd, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(i32, 1)));

        // 3. Bind to all interfaces on mDNS port
        const bind_addr = try net.Address.parseIp("0.0.0.0", MULTICAST_PORT);
        try posix.bind(fd, &bind_addr.any, bind_addr.getOsSockLen());

        // 4. Join Multicast Group
        const mcast_addr = try net.Address.parseIp(MULTICAST_ADDR, 0);
        const mreq = ip_mreq{
            .imr_multiaddr = mcast_addr.in.sa.addr,
            .imr_interface = 0, // Default interface
        };
        try posix.setsockopt(fd, posix.IPPROTO.IP, std.os.linux.IP.ADD_MEMBERSHIP, &std.mem.toBytes(mreq));

        return DiscoveryService{
            .allocator = allocator,
            .fd = fd,
            .port = local_port,
        };
    }

    pub fn deinit(self: *DiscoveryService) void {
        posix.close(self.fd);
    }

    /// Broadcast a Libertaria service announcement
    pub fn announce(self: *DiscoveryService) !void {
        // Construct a minimal mDNS Answer packet (DNS response)
        // PTR: _libertaria._udp.local -> <short_did>._libertaria._udp.local

        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        // 1. Transaction ID (0 for mDNS responses)
        try writer.writeInt(u16, 0, .big);
        // 2. Flags (0x8400: Response, Authoritative)
        try writer.writeInt(u16, 0x8400, .big);
        // 3. Question Count (0)
        try writer.writeInt(u16, 0, .big);
        // 4. Answer Record Count (1)
        try writer.writeInt(u16, 1, .big);
        // 5. Authority Record Count (0)
        try writer.writeInt(u16, 0, .big);
        // 6. Additional Record Count (0)
        try writer.writeInt(u16, 0, .big);

        // 7. Answer: Name "_libertaria._udp.local"
        try writeDnsName(writer, "_libertaria._udp.local");

        // 8. Type PTR (12), Class IN (1)
        try writer.writeInt(u16, 12, .big);
        try writer.writeInt(u16, 1, .big);

        // 9. TTL (120s)
        try writer.writeInt(u32, 120, .big);

        // 10. Data Length and RDATA
        // For Week 28, just point back to the same name or a static ID stub
        // Real logic will use <short_did>._libertaria._udp.local
        const target = "node-id-placeholder._libertaria._udp.local";
        try writer.writeInt(u16, @intCast(getDnsNameLen(target)), .big);
        try writeDnsName(writer, target);

        const dest = try net.Address.parseIp(MULTICAST_ADDR, MULTICAST_PORT);
        _ = try posix.sendto(self.fd, fbs.getWritten(), 0, &dest.any, dest.getOsSockLen());
    }

    fn getDnsNameLen(name: []const u8) usize {
        var count: usize = 1; // Final null
        var it = std.mem.splitScalar(u8, name, '.');
        while (it.next()) |part| {
            count += 1 + part.len;
        }
        return count;
    }

    fn writeDnsName(writer: anytype, name: []const u8) !void {
        var it = std.mem.splitScalar(u8, name, '.');
        while (it.next()) |part| {
            try writer.writeByte(@intCast(part.len));
            try writer.writeAll(part);
        }
        try writer.writeByte(0);
    }

    /// Query for other Libertaria nodes
    pub fn query(self: *DiscoveryService) !void {
        var buf: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        // 1. Transaction ID (0)
        try writer.writeInt(u16, 0, .big);
        // 2. Flags (0x0000: Standard Query)
        try writer.writeInt(u16, 0x0000, .big);
        // 3. Question Count (1)
        try writer.writeInt(u16, 1, .big);
        // 4. Answer Record Count (0)
        try writer.writeInt(u16, 0, .big);
        // 5. Authority Record Count (0)
        try writer.writeInt(u16, 0, .big);
        // 6. Additional Record Count (0)
        try writer.writeInt(u16, 0, .big);

        // 7. Question: Name "_libertaria._udp.local"
        try writeDnsName(writer, "_libertaria._udp.local");

        // 8. Type PTR (12), Class IN (1)
        try writer.writeInt(u16, 12, .big);
        try writer.writeInt(u16, 1, .big);

        const dest = try net.Address.parseIp(MULTICAST_ADDR, MULTICAST_PORT);
        _ = try posix.sendto(self.fd, fbs.getWritten(), 0, &dest.any, dest.getOsSockLen());
    }

    /// Parse an incoming mDNS packet and update the peer table
    pub fn handlePacket(self: *DiscoveryService, peer_table: anytype, buf: []const u8, sender: net.Address) !void {
        if (buf.len < 12) return; // Too small

        // Skip Header (12 bytes)
        const answer_count = std.mem.readInt(u16, buf[6..8], .big);
        if (answer_count == 0) return;

        // Skip Question section if any (simplified: we expect responses to our query or gratuitous responses)
        // For local discovery, we mostly care about Answers.

        // This is a VERY MINIMAL parser for Week 28.
        // It looks for the "_libertaria._udp.local" string and assumes the following PTR.
        if (std.mem.indexOf(u8, buf, "_libertaria")) |_| {
            // Found a Libertaria record!
            // In a real implementation, we'd parse SRV/TXT for the actual port and DID.
            // For MVP, if we receive a Libertaria-tagged packet, we trust the sender's IP.
            // (Port is still tricky since discovery is on 5353 but service is on 8710).

            // TODO: Extract DID from TXT record
            var mock_did = [_]u8{0} ** 8;
            @memcpy(mock_did[0..4], "NODE");

            // We assume the peer is running on its default port or we need SRV record.
            // For now, use the sender's IP but the standard port.
            var peer_addr = sender;
            peer_addr.setPort(self.port); // Fallback to our configured port if unknown

            try peer_table.updatePeer(mock_did, peer_addr);
        }
    }
};
