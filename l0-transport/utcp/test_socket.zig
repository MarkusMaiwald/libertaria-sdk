const std = @import("std");
const socket = @import("socket.zig");
const lwf = @import("../lwf.zig");

test "UTCP socket init and loopback" {
    const allocator = std.testing.allocator;
    const addr = try std.net.Address.parseIp("127.0.0.1", 0); // Port 0 for ephemeral

    var server = try socket.UTCP.init(addr);
    defer server.deinit();

    const server_addr = try server.getLocalAddress();

    var client = try socket.UTCP.init(try std.net.Address.parseIp("127.0.0.1", 0));
    defer client.deinit();

    // 1. Prepare frame
    var frame = try lwf.LWFFrame.init(allocator, 32);
    defer frame.deinit(allocator);
    @memcpy(frame.payload, "UTCP-Protocol-Test-Payload-1234");
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
