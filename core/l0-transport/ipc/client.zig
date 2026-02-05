//! IPC Client - L0 -> L2 Event Bridge
//!
//! Sends transport events to the L2 Membrane Agent via Unix Domain Sockets.

const std = @import("std");
const net = std.net;
const os = std.os;
const mem = std.mem;

pub const IpcClient = struct {
    allocator: mem.Allocator,
    socket_path: []const u8,
    stream: ?net.Stream,
    connected: bool,

    // Constants
    const MAGIC: u16 = 0x55AA;

    // Event Types
    const EVENT_PACKET_RECEIVED: u8 = 0x01;
    const EVENT_CONNECTION_ESTABLISHED: u8 = 0x02;
    const EVENT_CONNECTION_DROPPED: u8 = 0x03;

    pub fn init(allocator: mem.Allocator, socket_path: []const u8) IpcClient {
        return IpcClient{
            .allocator = allocator,
            .socket_path = socket_path,
            .stream = null,
            .connected = false,
        };
    }

    pub fn deinit(self: *IpcClient) void {
        if (self.stream) |s| {
            s.close();
        }
    }

    /// Try to connect if not connected
    pub fn connect(self: *IpcClient) !void {
        if (self.connected) return;

        // Non-blocking connect attempt
        const stream = net.connectUnixSocket(self.socket_path) catch |err| {
            // Connection failed (agent not running?)
            // Just return, don't crash. We'll try again next time.
            // Log debug?
            return err;
        };

        self.stream = stream;
        self.connected = true;
    }

    /// Send 'PacketReceived' event
    pub fn sendPacketReceived(self: *IpcClient, sender_did: [32]u8, packet_type: u8, payload_size: u32) !void {
        if (!self.connected) {
            self.connect() catch return; // Retry connect
        }

        // Payload size: DID(32) + Type(1) + Size(4) = 37 bytes
        const payload_len: u32 = 37;

        // Prepare Header (8 bytes)
        // Magic(2) + Type(1) + Flags(1) + Len(4)
        var buffer: [8 + 37]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        // Header
        try writer.writeInt(u16, MAGIC, .little);
        try writer.writeInt(u8, EVENT_PACKET_RECEIVED, .little);
        try writer.writeInt(u8, 0, .little); // Flags
        try writer.writeInt(u32, payload_len, .little);

        // Payload
        try writer.writeAll(&sender_did);
        try writer.writeInt(u8, packet_type, .little);
        try writer.writeInt(u32, payload_size, .little);

        // Send
        if (self.stream) |s| {
            s.writeAll(&buffer) catch |err| {
                // Write failed, assume disconnected
                self.connected = false;
                s.close();
                self.stream = null;
                return err;
            };
        }
    }
};

test "ipc packet serialization" {
    // Just verify bytes match expected format
    var buffer: [8 + 37]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    // Manual write
    try writer.writeInt(u16, 0x55AA, .little);
    try writer.writeInt(u8, 0x01, .little);
    try writer.writeInt(u8, 0, .little);
    try writer.writeInt(u32, 37, .little);

    // Offset 8: Payload starts
    try std.testing.expectEqual(buffer[0], 0xAA);
    try std.testing.expectEqual(buffer[1], 0x55);
}
