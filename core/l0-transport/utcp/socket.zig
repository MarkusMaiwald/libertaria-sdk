//! RFC-0004: UTCP (Unreliable Transport Protocol) over UDP

const std = @import("std");
const lwf = @import("../lwf.zig");
const posix = std.posix;

/// UTCP Socket abstraction for sending and receiving LWF frames
pub const UTCP = struct {
    fd: posix.socket_t,

    /// Initialize UTCP socket by binding to an address
    pub fn init(allocator: std.mem.Allocator, address: std.net.Address) !UTCP {
        _ = allocator;
        const fd = try posix.socket(
            address.any.family,
            posix.SOCK.DGRAM | posix.SOCK.CLOEXEC,
            posix.IPPROTO.UDP,
        );
        errdefer posix.close(fd);

        try posix.bind(fd, &address.any, address.getOsSockLen());

        return UTCP{
            .fd = fd,
        };
    }

    /// Close the socket
    pub fn deinit(self: *UTCP) void {
        posix.close(self.fd);
    }

    /// Encode and send an LWF frame to a target address
    pub fn sendFrame(self: *UTCP, target: std.net.Address, frame: *const lwf.LWFFrame, allocator: std.mem.Allocator) !void {
        const encoded = try frame.encode(allocator);
        defer allocator.free(encoded);

        const sent = try posix.sendto(
            self.fd,
            encoded,
            0,
            &target.any,
            target.getOsSockLen(),
        );

        if (sent != encoded.len) {
            return error.PartialWrite;
        }
    }

    /// Receive a frame from the network
    /// Performs non-allocating header validation before processing payload
    pub fn receiveFrame(self: *UTCP, allocator: std.mem.Allocator, buffer: []u8) !ReceiveResult {
        var src_addr: posix.sockaddr = undefined;
        var src_len: posix.socklen_t = @sizeOf(posix.sockaddr);

        const bytes_received = try posix.recvfrom(
            self.fd,
            buffer,
            0,
            &src_addr,
            &src_len,
        );

        const data = buffer[0..bytes_received];

        // 1. Fast Header Validation (No Allocation)
        if (data.len < lwf.LWFHeader.SIZE) {
            return error.FrameUnderflow;
        }

        var header_bytes: [lwf.LWFHeader.SIZE]u8 = undefined;
        @memcpy(&header_bytes, data[0..lwf.LWFHeader.SIZE]);
        const header = lwf.LWFHeader.fromBytes(&header_bytes);

        if (!header.isValid()) {
            return error.InvalidMagic;
        }

        // 2. Entropy Fast-Path (DoS Defense) - disabled, needs entropy module from l1_identity
        // if (header.flags & lwf.LWFFlags.HAS_ENTROPY != 0) {
        //     return error.NotImplemented; // Entropy validation requires l1_identity module
        // }

        // 3. Decode the rest (Allocates payload)
        const frame = try lwf.LWFFrame.decode(allocator, data);

        return ReceiveResult{
            .frame = frame,
            .sender = std.net.Address{ .any = src_addr },
        };
    }

    /// Get local address of the socket
    pub fn getLocalAddress(self: *UTCP) !std.net.Address {
        var addr: posix.sockaddr = undefined;
        var len: posix.socklen_t = @sizeOf(posix.sockaddr);
        try posix.getsockname(self.fd, &addr, &len);
        return std.net.Address{ .any = addr };
    }
};

pub const ReceiveResult = struct {
    frame: lwf.LWFFrame,
    sender: std.net.Address,
};
test "UTCP socket init and loopback" {
    const allocator = std.testing.allocator;
    const addr = try std.net.Address.parseIp("127.0.0.1", 0); // Port 0 for ephemeral

    var server = try UTCP.init(allocator, addr);
    defer server.deinit();

    const server_addr = try server.getLocalAddress();

    var client = try UTCP.init(allocator, try std.net.Address.parseIp("127.0.0.1", 0));
    defer client.deinit();

    // 1. Prepare frame
    var frame = try lwf.LWFFrame.init(allocator, 32);
    defer frame.deinit(allocator);
    @memcpy(frame.payload, "UTCP-Protocol-Test-Payload-01234");
    frame.header.payload_len = 32;
    frame.updateChecksum();

    // 2. Send
    try client.sendFrame(server_addr, &frame, allocator);

    // 3. Receive
    var receive_buf: [1500]u8 = undefined;
    const result = try server.receiveFrame(allocator, &receive_buf);
    var received_frame = result.frame;
    defer received_frame.deinit(allocator);

    // 4. Verify
    try std.testing.expectEqualSlices(u8, frame.payload, received_frame.payload);
    try std.testing.expect(received_frame.verifyChecksum());
}

// Note: Entropy validation test disabled - requires l1_identity module
// test "UTCP socket DoS defense: invalid entropy stamp" {
//     const allocator = std.testing.allocator;
//     const addr = try std.net.Address.parseIp("127.0.0.1", 0);
//
//     var server = try UTCP.init(allocator, addr);
//     defer server.deinit();
//     const server_addr = try server.getLocalAddress();
//
//     var client = try UTCP.init(allocator, try std.net.Address.parseIp("127.0.0.1", 0));
//     defer client.deinit();
//
//     // 1. Prepare frame with HAS_ENTROPY but garbage stamp
//     var frame = try lwf.LWFFrame.init(allocator, 100);
//     defer frame.deinit(allocator);
//     frame.header.flags |= lwf.LWFFlags.HAS_ENTROPY;
//     frame.header.entropy_difficulty = 20; // High difficulty
//     @memset(frame.payload[0..77], 0);
//     // Set valid timestamp (fresh)
//     // Offset: Hash(32) + Nonce(16) + Salt(16) + Diff(1) + Mem(2) = 67
//     const now = @as(u64, @intCast(std.time.timestamp()));
//     std.mem.writeInt(u64, frame.payload[67..75], now, .big);
//
//     // 2. Send
//     try client.sendFrame(server_addr, &frame, allocator);
//
//     // 3. Receive - should fail with InsufficientDifficulty
//     var receive_buf: [1500]u8 = undefined;
//     const result = server.receiveFrame(allocator, &receive_buf);
//
//     try std.testing.expectError(error.InsufficientDifficulty, result);
// }
