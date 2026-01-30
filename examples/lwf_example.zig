//! Example: Creating and encoding LWF frames
//!
//! This demonstrates basic usage of the L0 transport layer.

const std = @import("std");
const lwf = @import("../l0-transport/lwf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();


    std.debug.print("Libertaria SDK - LWF Frame Example\n", .{});
    std.debug.print("===================================\n\n", .{});

    // Create LWF frame
    var frame = try lwf.LWFFrame.init(allocator, 100);
    defer frame.deinit(allocator);

    std.debug.print("1. Created LWF frame:\n", .{});
    std.debug.print("   Header size: {} bytes\n", .{lwf.LWFHeader.SIZE});
    std.debug.print("   Payload size: {} bytes\n", .{frame.payload.len});
    std.debug.print("   Trailer size: {} bytes\n", .{lwf.LWFTrailer.SIZE});
    std.debug.print("   Total size: {} bytes\n\n", .{frame.size()});

    // Set frame headers
    frame.header.service_type = std.mem.nativeToBig(u16, 0x0A00); // FEED_WORLD_POST
    frame.header.flags = lwf.LWFFlags.ENCRYPTED | lwf.LWFFlags.SIGNED;
    frame.header.frame_class = @intFromEnum(lwf.FrameClass.standard);
    frame.header.timestamp = std.mem.nativeToBig(u64, @as(u64, @intCast(std.time.timestamp())));
    frame.header.payload_len = std.mem.nativeToBig(u16, @as(u16, @intCast(frame.payload.len)));

    // Fill payload with example data
    const message = "Hello, Libertaria Wire Frame Protocol!";
    @memcpy(frame.payload[0..message.len], message);

    std.debug.print("2. Populated frame:\n", .{});
    std.debug.print("   Service type: 0x{X:0>4}\n", .{std.mem.bigToNative(u16, frame.header.service_type)});
    std.debug.print("   Flags: 0x{X:0>2} ", .{frame.header.flags});
    if (frame.header.flags & lwf.LWFFlags.ENCRYPTED != 0) {
        std.debug.print("(ENCRYPTED) ", .{});
    }
    if (frame.header.flags & lwf.LWFFlags.SIGNED != 0) {
        std.debug.print("(SIGNED) ", .{});
    }
    std.debug.print("\n", .{});
    std.debug.print("   Frame class: {s}\n", .{@tagName(lwf.FrameClass.standard)});
    std.debug.print("   Payload: \"{s}\"\n\n", .{message});

    // Calculate and set checksum
    frame.updateChecksum();

    std.debug.print("3. Checksum:\n", .{});
    std.debug.print("   Calculated: 0x{X:0>8}\n", .{std.mem.bigToNative(u32, frame.trailer.checksum)});
    std.debug.print("   Verified: {}\n\n", .{frame.verifyChecksum()});

    // Encode frame to bytes
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    std.debug.print("4. Encoded frame:\n", .{});
    std.debug.print("   Size: {} bytes\n", .{encoded.len});
    std.debug.print("   First 16 bytes: ", .{});
    for (encoded[0..16]) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n\n", .{});

    // Decode frame back
    var decoded = try lwf.LWFFrame.decode(allocator, encoded);
    defer decoded.deinit(allocator);

    std.debug.print("5. Decoded frame:\n", .{});
    std.debug.print("   Magic: {s}\n", .{decoded.header.magic[0..3]});
    std.debug.print("   Version: {}\n", .{decoded.header.version});
    std.debug.print("   Service type: 0x{X:0>4}\n", .{std.mem.bigToNative(u16, decoded.header.service_type)});
    std.debug.print("   Payload: \"{s}\"\n", .{decoded.payload[0..message.len]});
    std.debug.print("   Checksum valid: {}\n\n", .{decoded.verifyChecksum()});

    std.debug.print("✅ LWF frame encoding/decoding works!\n", .{});
}
