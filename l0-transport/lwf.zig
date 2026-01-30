//! RFC-0000: Libertaria Wire Frame Protocol
//!
//! This module implements the core LWF frame structure for L0 transport.
//!
//! Key features:
//! - Fixed-size header (64 bytes)
//! - Variable payload (up to 8900 bytes based on frame class)
//! - Fixed-size trailer (36 bytes)
//! - Checksum verification (CRC32-C)
//! - Signature support (Ed25519)
//!
//! Frame structure:
//! ┌──────────────────┐
//! │  Header (64B)    │
//! ├──────────────────┤
//! │  Payload (var)   │
//! ├──────────────────┤
//! │  Trailer (36B)   │
//! └──────────────────┘

const std = @import("std");

/// RFC-0000 Section 4.1: Frame size classes
pub const FrameClass = enum(u8) {
    micro = 0x00,      // 128 bytes
    tiny = 0x01,       // 512 bytes
    standard = 0x02,   // 1350 bytes (default)
    large = 0x03,      // 4096 bytes
    jumbo = 0x04,      // 9000 bytes

    pub fn maxPayloadSize(self: FrameClass) usize {
        return switch (self) {
            .micro => 128 - LWFHeader.SIZE - LWFTrailer.SIZE,
            .tiny => 512 - LWFHeader.SIZE - LWFTrailer.SIZE,
            .standard => 1350 - LWFHeader.SIZE - LWFTrailer.SIZE,
            .large => 4096 - LWFHeader.SIZE - LWFTrailer.SIZE,
            .jumbo => 9000 - LWFHeader.SIZE - LWFTrailer.SIZE,
        };
    }
};

/// RFC-0000 Section 4.3: Frame flags
pub const LWFFlags = struct {
    pub const ENCRYPTED: u8 = 0x01;        // Payload is encrypted
    pub const SIGNED: u8 = 0x02;           // Trailer has signature
    pub const RELAYABLE: u8 = 0x04;        // Can be relayed by nodes
    pub const HAS_ENTROPY: u8 = 0x08;      // Includes Entropy Stamp
    pub const FRAGMENTED: u8 = 0x10;       // Part of fragmented message
    pub const PRIORITY: u8 = 0x20;         // High-priority frame
};

/// RFC-0000 Section 4.2: LWF Header (64 bytes fixed)
pub const LWFHeader = extern struct {
    magic: [4]u8,               // "LWF\0"
    version: u8,                // 0x01
    flags: u8,                  // Bitfield (see LWFFlags)
    service_type: u16,          // Big-endian, 0x0A00-0x0AFF for Feed
    source_hint: [20]u8,        // Blake3 truncated DID hint
    dest_hint: [20]u8,          // Blake3 truncated DID hint
    sequence: u32,              // Big-endian, anti-replay counter
    timestamp: u64,             // Big-endian, Unix epoch milliseconds
    payload_len: u16,           // Big-endian, actual payload size
    entropy_difficulty: u8,     // Entropy Stamp difficulty (0-255)
    frame_class: u8,            // FrameClass enum value

    pub const SIZE: usize = 64;

    /// Initialize header with default values
    pub fn init() LWFHeader {
        return .{
            .magic = [_]u8{ 'L', 'W', 'F', 0 },
            .version = 0x01,
            .flags = 0,
            .service_type = 0,
            .source_hint = [_]u8{0} ** 20,
            .dest_hint = [_]u8{0} ** 20,
            .sequence = 0,
            .timestamp = 0,
            .payload_len = 0,
            .entropy_difficulty = 0,
            .frame_class = @intFromEnum(FrameClass.standard),
        };
    }

    /// Validate header magic bytes
    pub fn isValid(self: *const LWFHeader) bool {
        const expected_magic = [4]u8{ 'L', 'W', 'F', 0 };
        return std.mem.eql(u8, &self.magic, &expected_magic) and self.version == 0x01;
    }

    /// Serialize header to exactly 64 bytes (no padding)
    pub fn toBytes(self: *const LWFHeader, buffer: *[64]u8) void {
        var offset: usize = 0;

        // magic: [4]u8
        @memcpy(buffer[offset..][0..4], &self.magic);
        offset += 4;

        // version: u8
        buffer[offset] = self.version;
        offset += 1;

        // flags: u8
        buffer[offset] = self.flags;
        offset += 1;

        // service_type: u16 (already big-endian, copy bytes directly)
        @memcpy(buffer[offset..][0..2], std.mem.asBytes(&self.service_type));
        offset += 2;

        // source_hint: [20]u8
        @memcpy(buffer[offset..][0..20], &self.source_hint);
        offset += 20;

        // dest_hint: [20]u8
        @memcpy(buffer[offset..][0..20], &self.dest_hint);
        offset += 20;

        // sequence: u32 (already big-endian, copy bytes directly)
        @memcpy(buffer[offset..][0..4], std.mem.asBytes(&self.sequence));
        offset += 4;

        // timestamp: u64 (already big-endian, copy bytes directly)
        @memcpy(buffer[offset..][0..8], std.mem.asBytes(&self.timestamp));
        offset += 8;

        // payload_len: u16 (already big-endian, copy bytes directly)
        @memcpy(buffer[offset..][0..2], std.mem.asBytes(&self.payload_len));
        offset += 2;

        // entropy_difficulty: u8
        buffer[offset] = self.entropy_difficulty;
        offset += 1;

        // frame_class: u8
        buffer[offset] = self.frame_class;
        // offset += 1; // Final field, no need to increment

        std.debug.assert(offset + 1 == 64); // Verify we wrote exactly 64 bytes
    }

    /// Deserialize header from exactly 64 bytes
    pub fn fromBytes(buffer: *const [64]u8) LWFHeader {
        var header: LWFHeader = undefined;
        var offset: usize = 0;

        // magic: [4]u8
        @memcpy(&header.magic, buffer[offset..][0..4]);
        offset += 4;

        // version: u8
        header.version = buffer[offset];
        offset += 1;

        // flags: u8
        header.flags = buffer[offset];
        offset += 1;

        // service_type: u16 (already big-endian, copy bytes directly)
        @memcpy(std.mem.asBytes(&header.service_type), buffer[offset..][0..2]);
        offset += 2;

        // source_hint: [20]u8
        @memcpy(&header.source_hint, buffer[offset..][0..20]);
        offset += 20;

        // dest_hint: [20]u8
        @memcpy(&header.dest_hint, buffer[offset..][0..20]);
        offset += 20;

        // sequence: u32 (already big-endian, copy bytes directly)
        @memcpy(std.mem.asBytes(&header.sequence), buffer[offset..][0..4]);
        offset += 4;

        // timestamp: u64 (already big-endian, copy bytes directly)
        @memcpy(std.mem.asBytes(&header.timestamp), buffer[offset..][0..8]);
        offset += 8;

        // payload_len: u16 (already big-endian, copy bytes directly)
        @memcpy(std.mem.asBytes(&header.payload_len), buffer[offset..][0..2]);
        offset += 2;

        // entropy_difficulty: u8
        header.entropy_difficulty = buffer[offset];
        offset += 1;

        // frame_class: u8
        header.frame_class = buffer[offset];
        // offset += 1; // Final field

        return header;
    }
};

/// RFC-0000 Section 4.7: LWF Trailer (36 bytes fixed)
pub const LWFTrailer = extern struct {
    signature: [32]u8,          // Ed25519 signature (or zeros if not signed)
    checksum: u32,              // CRC32-C, big-endian

    pub const SIZE: usize = 36;

    /// Initialize trailer with zeros
    pub fn init() LWFTrailer {
        return .{
            .signature = [_]u8{0} ** 32,
            .checksum = 0,
        };
    }

    /// Serialize trailer to exactly 36 bytes (no padding)
    pub fn toBytes(self: *const LWFTrailer, buffer: *[36]u8) void {
        var offset: usize = 0;

        // signature: [32]u8
        @memcpy(buffer[offset..][0..32], &self.signature);
        offset += 32;

        // checksum: u32 (already big-endian, copy bytes directly)
        @memcpy(buffer[offset..][0..4], std.mem.asBytes(&self.checksum));
        // offset += 4;

        std.debug.assert(offset + 4 == 36); // Verify we wrote exactly 36 bytes
    }

    /// Deserialize trailer from exactly 36 bytes
    pub fn fromBytes(buffer: *const [36]u8) LWFTrailer {
        var trailer: LWFTrailer = undefined;
        var offset: usize = 0;

        // signature: [32]u8
        @memcpy(&trailer.signature, buffer[offset..][0..32]);
        offset += 32;

        // checksum: u32 (already big-endian, copy bytes directly)
        @memcpy(std.mem.asBytes(&trailer.checksum), buffer[offset..][0..4]);
        // offset += 4;

        return trailer;
    }
};

/// RFC-0000 Section 4.1: Complete LWF Frame
pub const LWFFrame = struct {
    header: LWFHeader,
    payload: []u8,
    trailer: LWFTrailer,

    /// Create new frame with allocated payload
    pub fn init(allocator: std.mem.Allocator, payload_size: usize) !LWFFrame {
        const payload = try allocator.alloc(u8, payload_size);
        @memset(payload, 0);

        return .{
            .header = LWFHeader.init(),
            .payload = payload,
            .trailer = LWFTrailer.init(),
        };
    }

    /// Free payload memory
    pub fn deinit(self: *LWFFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }

    /// Total frame size (header + payload + trailer)
    pub fn size(self: *const LWFFrame) usize {
        return LWFHeader.SIZE + self.payload.len + LWFTrailer.SIZE;
    }

    /// Encode frame to bytes (allocates new buffer)
    pub fn encode(self: *const LWFFrame, allocator: std.mem.Allocator) ![]u8 {
        const total_size = self.size();
        var buffer = try allocator.alloc(u8, total_size);

        // Serialize header (exactly 64 bytes)
        var header_bytes: [64]u8 = undefined;
        self.header.toBytes(&header_bytes);
        @memcpy(buffer[0..64], &header_bytes);

        // Copy payload
        @memcpy(buffer[64 .. 64 + self.payload.len], self.payload);

        // Serialize trailer (exactly 36 bytes)
        var trailer_bytes: [36]u8 = undefined;
        self.trailer.toBytes(&trailer_bytes);
        const trailer_start = 64 + self.payload.len;
        @memcpy(buffer[trailer_start .. trailer_start + 36], &trailer_bytes);

        return buffer;
    }

    /// Decode frame from bytes (allocates payload)
    pub fn decode(allocator: std.mem.Allocator, data: []const u8) !LWFFrame {
        // Minimum frame size check
        if (data.len < 64 + 36) {
            return error.FrameTooSmall;
        }

        // Parse header (first 64 bytes)
        var header_bytes: [64]u8 = undefined;
        @memcpy(&header_bytes, data[0..64]);
        const header = LWFHeader.fromBytes(&header_bytes);

        // Validate header
        if (!header.isValid()) {
            return error.InvalidHeader;
        }

        // Extract payload length
        const payload_len = @as(usize, @intCast(std.mem.bigToNative(u16, header.payload_len)));

        // Verify frame size matches
        if (data.len < 64 + payload_len + 36) {
            return error.InvalidPayloadLength;
        }

        // Allocate and copy payload
        const payload = try allocator.alloc(u8, payload_len);
        @memcpy(payload, data[64 .. 64 + payload_len]);

        // Parse trailer
        const trailer_start = 64 + payload_len;
        var trailer_bytes: [36]u8 = undefined;
        @memcpy(&trailer_bytes, data[trailer_start .. trailer_start + 36]);
        const trailer = LWFTrailer.fromBytes(&trailer_bytes);

        return .{
            .header = header,
            .payload = payload,
            .trailer = trailer,
        };
    }

    /// Calculate CRC32-C checksum of header + payload
    pub fn calculateChecksum(self: *const LWFFrame) u32 {
        var hasher = std.hash.Crc32.init();

        // Hash header (exactly 64 bytes)
        var header_bytes: [64]u8 = undefined;
        self.header.toBytes(&header_bytes);
        hasher.update(&header_bytes);

        // Hash payload
        hasher.update(self.payload);

        return hasher.final();
    }

    /// Verify checksum matches
    pub fn verifyChecksum(self: *const LWFFrame) bool {
        const computed = self.calculateChecksum();
        const stored = std.mem.bigToNative(u32, self.trailer.checksum);
        return computed == stored;
    }

    /// Update checksum field in trailer
    pub fn updateChecksum(self: *LWFFrame) void {
        const checksum = self.calculateChecksum();
        self.trailer.checksum = std.mem.nativeToBig(u32, checksum);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LWFFrame creation" {
    const allocator = std.testing.allocator;

    var frame = try LWFFrame.init(allocator, 100);
    defer frame.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 64 + 100 + 36), frame.size());
    try std.testing.expectEqual(@as(u8, 'L'), frame.header.magic[0]);
    try std.testing.expectEqual(@as(u8, 0x01), frame.header.version);
}

test "LWFFrame encode/decode roundtrip" {
    const allocator = std.testing.allocator;

    // Create frame
    var frame = try LWFFrame.init(allocator, 10);
    defer frame.deinit(allocator);

    // Populate frame
    frame.header.service_type = std.mem.nativeToBig(u16, 0x0A00); // FEED_WORLD_POST
    frame.header.payload_len = std.mem.nativeToBig(u16, 10);
    frame.header.timestamp = std.mem.nativeToBig(u64, 1234567890);
    @memcpy(frame.payload, "HelloWorld");
    frame.updateChecksum();

    // Encode
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    try std.testing.expectEqual(@as(usize, 64 + 10 + 36), encoded.len);

    // Decode
    var decoded = try LWFFrame.decode(allocator, encoded);
    defer decoded.deinit(allocator);

    // Verify
    try std.testing.expectEqualSlices(u8, "HelloWorld", decoded.payload);
    try std.testing.expectEqual(frame.header.service_type, decoded.header.service_type);
    try std.testing.expectEqual(frame.header.timestamp, decoded.header.timestamp);
}

test "LWFFrame checksum verification" {
    const allocator = std.testing.allocator;

    var frame = try LWFFrame.init(allocator, 20);
    defer frame.deinit(allocator);

    @memcpy(frame.payload, "Test payload content");
    frame.updateChecksum();

    // Should pass
    try std.testing.expect(frame.verifyChecksum());

    // Corrupt payload
    frame.payload[0] = 'X';

    // Should fail
    try std.testing.expect(!frame.verifyChecksum());
}

test "FrameClass payload sizes" {
    try std.testing.expectEqual(@as(usize, 28), FrameClass.micro.maxPayloadSize());
    try std.testing.expectEqual(@as(usize, 412), FrameClass.tiny.maxPayloadSize());
    try std.testing.expectEqual(@as(usize, 1250), FrameClass.standard.maxPayloadSize());
    try std.testing.expectEqual(@as(usize, 3996), FrameClass.large.maxPayloadSize());
    try std.testing.expectEqual(@as(usize, 8900), FrameClass.jumbo.maxPayloadSize());
}
