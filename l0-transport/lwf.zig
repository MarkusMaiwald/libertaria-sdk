//! RFC-0000: Libertaria Wire Frame Protocol (v2)
//!
//! This module implements the core LWF frame structure for L0 transport.
//! Optimized for "Fast Drop" routing efficiency.
//!
//! Key features:
//! - Fixed-size header (88 bytes) - Router Optimized Order
//! - Variable payload (up to 9000+ bytes)
//! - Fixed-size trailer (36 bytes)
//! - Checksum verification (CRC32-C)
//! - Signature support (Ed25519)
//! - Explicit SessionID (16 bytes) for flow filtering
//!
//! Header Layout (88 bytes):
//! ┌───────────────────────┬───────┐
//! │ 00-03: Magic (4)      │ Fast  │
//! │ 04-27: Dest Hint (24) │ Route │
//! │ 28-51: Src Hint (24)  │ Filt  │
//! ├───────────────────────┼───────┤
//! │ 52-67: SessionID (16) │ Flow  │
//! │ 68-71: Sequence (4)   │ Order │
//! ├───────────────────────┼───────┤
//! │ 72-73: Service (2)    │ Polcy │
//! │ 74-75: Length (2)     │ Alloc │
//! │ 76-79: Meta (4)       │ Misc  │
//! │ 80-87: Timestamp (8)  │ TTL   │
//! └───────────────────────┴───────┘

const std = @import("std");

/// RFC-0000: Frame Types / Classes
pub const FrameClass = enum(u8) {
    micro = 0x00, // 128 bytes (Microframe)
    mini = 0x01, // 512 bytes (Miniframe) - formerly Tiny
    standard = 0x02, // 1350 bytes (Frame)
    big = 0x03, // 4096 bytes (Bigframe) - formerly Large
    jumbo = 0x04, // 9000 bytes (Jumboframe)
    variable = 0xFF, // Custom/Unlimited (Variableframe)

    pub fn maxPayloadSize(self: FrameClass) usize {
        const overhead = LWFHeader.SIZE + LWFTrailer.SIZE; // 88 + 36 = 124 bytes
        return switch (self) {
            .micro => if (128 > overhead) 128 - overhead else 0,
            .mini => 512 - overhead,
            .standard => 1350 - overhead,
            .big => 4096 - overhead,
            .jumbo => 9000 - overhead,
            .variable => std.math.maxInt(usize), // Limited by allocator/MTU
        };
    }
};

/// RFC-0000: Frame flags
pub const LWFFlags = struct {
    pub const ENCRYPTED: u8 = 0x01; // Payload is encrypted
    pub const SIGNED: u8 = 0x02; // Trailer has signature
    pub const RELAYABLE: u8 = 0x04; // Can be relayed by nodes
    pub const HAS_ENTROPY: u8 = 0x08; // Includes Entropy Stamp (Payload Prefix)
    pub const FRAGMENTED: u8 = 0x10; // Part of fragmented message
    pub const PRIORITY: u8 = 0x20; // High-priority frame
};

/// RFC-0000: LWF Header (88 bytes fixed)
/// Order optimized for Router Efficiency: Routing -> Flow -> Context -> Time
pub const LWFHeader = struct {
    pub const VERSION: u8 = 0x02;
    pub const SIZE: usize = 88;

    // RFC-0121: Service Types
    pub const ServiceType = struct {
        pub const DATA_TRANSPORT: u16 = 0x0001;
        pub const SLASH_PROTOCOL: u16 = 0x0002;
        pub const IDENTITY_SIGNAL: u16 = 0x0003;
        pub const ECONOMIC_SETTLEMENT: u16 = 0x0004;
        pub const RELAY_FORWARD: u16 = 0x0005;

        // Streaming Media (0x0800-0x08FF)
        pub const STREAM_AUDIO: u16 = 0x0800;
        pub const STREAM_VIDEO: u16 = 0x0801;
        pub const STREAM_DATA: u16 = 0x0802;

        // P2P / Swarm (0x0B00-0x0BFF) - Low Priority / Bulk
        pub const SWARM_MANIFEST: u16 = 0x0B00; // Handshake/InfoDict
        pub const SWARM_HAVE: u16 = 0x0B01; // Bitfield
        pub const SWARM_REQUEST: u16 = 0x0B02; // Interest
        pub const SWARM_BLOCK: u16 = 0x0B03; // Data Payload
    };

    // 1. Identification & Routing (Top Priority)
    magic: [4]u8, // "LWF\0"
    dest_hint: [24]u8, // Blake3 truncated DID hint
    source_hint: [24]u8, // Blake3 truncated DID hint

    // 2. Flow & Ordering (Filtering)
    session_id: [16]u8, // Explicit Flow Context
    sequence: u32, // Anti-replay counter

    // 3. Technical Meta
    service_type: u16, // Protocol ID
    payload_len: u16, // Data size

    frame_class: u8, // FrameClass enum
    version: u8, // 0x02
    flags: u8, // Bitfield
    entropy_difficulty: u8, // PoW Target

    // 4. Temporal (Least Critical for Routing)
    timestamp: u64, // Nanoseconds

    /// Initialize header with default values
    pub fn init() LWFHeader {
        return .{
            .magic = [_]u8{ 'L', 'W', 'F', 0 },
            .version = VERSION,
            .flags = 0,
            .service_type = 0,
            .dest_hint = [_]u8{0} ** 24,
            .source_hint = [_]u8{0} ** 24,
            .session_id = [_]u8{0} ** 16,
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
        // Accept v1 or v2? Strict v2 for now.
        return std.mem.eql(u8, &self.magic, &expected_magic) and self.version == VERSION;
    }

    /// Serialize header to exactly 88 bytes
    pub fn toBytes(self: *const LWFHeader, buffer: *[88]u8) void {
        var offset: usize = 0;

        // 1. Magic (4)
        @memcpy(buffer[offset..][0..4], &self.magic);
        offset += 4;

        // 2. Dest Hint (24)
        @memcpy(buffer[offset..][0..24], &self.dest_hint);
        offset += 24;

        // 3. Src Hint (24)
        @memcpy(buffer[offset..][0..24], &self.source_hint);
        offset += 24;

        // 4. Session ID (16)
        @memcpy(buffer[offset..][0..16], &self.session_id);
        offset += 16;

        // 5. Sequence (4) big-endian
        std.mem.writeInt(u32, buffer[offset..][0..4], self.sequence, .big);
        offset += 4;

        // 6. Service Type (2) big-endian
        std.mem.writeInt(u16, buffer[offset..][0..2], self.service_type, .big);
        offset += 2;

        // 7. Payload Len (2) big-endian
        std.mem.writeInt(u16, buffer[offset..][0..2], self.payload_len, .big);
        offset += 2;

        // 8. Meta Fields (1 byte each)
        buffer[offset] = self.frame_class;
        offset += 1;
        buffer[offset] = self.version;
        offset += 1;
        buffer[offset] = self.flags;
        offset += 1;
        buffer[offset] = self.entropy_difficulty;
        offset += 1;

        // 9. Timestamp (8) big-endian
        std.mem.writeInt(u64, buffer[offset..][0..8], self.timestamp, .big);
        offset += 8;

        std.debug.assert(offset == 88);
    }

    /// Deserialize header from exactly 88 bytes
    pub fn fromBytes(buffer: *const [88]u8) LWFHeader {
        var header: LWFHeader = undefined;
        var offset: usize = 0;

        @memcpy(&header.magic, buffer[offset..][0..4]);
        offset += 4;
        @memcpy(&header.dest_hint, buffer[offset..][0..24]);
        offset += 24;
        @memcpy(&header.source_hint, buffer[offset..][0..24]);
        offset += 24;
        @memcpy(&header.session_id, buffer[offset..][0..16]);
        offset += 16;

        header.sequence = std.mem.readInt(u32, buffer[offset..][0..4], .big);
        offset += 4;
        header.service_type = std.mem.readInt(u16, buffer[offset..][0..2], .big);
        offset += 2;
        header.payload_len = std.mem.readInt(u16, buffer[offset..][0..2], .big);
        offset += 2;

        header.frame_class = buffer[offset];
        offset += 1;
        header.version = buffer[offset];
        offset += 1;
        header.flags = buffer[offset];
        offset += 1;
        header.entropy_difficulty = buffer[offset];
        offset += 1;

        header.timestamp = std.mem.readInt(u64, buffer[offset..][0..8], .big);
        offset += 8;

        return header;
    }
};

/// RFC-0000 Section 4.7: LWF Trailer (36 bytes fixed)
pub const LWFTrailer = extern struct {
    signature: [32]u8, // Ed25519 signature
    checksum: u32, // CRC32-C

    pub const SIZE: usize = 36;

    pub fn init() LWFTrailer {
        return .{
            .signature = [_]u8{0} ** 32,
            .checksum = 0,
        };
    }

    pub fn toBytes(self: *const LWFTrailer, buffer: *[36]u8) void {
        @memcpy(buffer[0..32], &self.signature);
        @memcpy(buffer[32..36], std.mem.asBytes(&self.checksum));
    }

    pub fn fromBytes(buffer: *const [36]u8) LWFTrailer {
        var trailer: LWFTrailer = undefined;
        @memcpy(&trailer.signature, buffer[0..32]);
        @memcpy(std.mem.asBytes(&trailer.checksum), buffer[32..36]);
        return trailer;
    }
};

/// RFC-0000 Section 4.1: Complete LWF Frame
pub const LWFFrame = struct {
    header: LWFHeader,
    payload: []u8,
    trailer: LWFTrailer,

    pub fn init(allocator: std.mem.Allocator, payload_size: usize) !LWFFrame {
        const payload = try allocator.alloc(u8, payload_size);
        @memset(payload, 0);
        return .{
            .header = LWFHeader.init(),
            .payload = payload,
            .trailer = LWFTrailer.init(),
        };
    }

    pub fn deinit(self: *const LWFFrame, allocator: std.mem.Allocator) void {
        allocator.free(self.payload);
    }

    pub fn size(self: *const LWFFrame) usize {
        return LWFHeader.SIZE + self.payload.len + LWFTrailer.SIZE;
    }

    pub fn encode(self: *const LWFFrame, allocator: std.mem.Allocator) ![]u8 {
        const total_size = self.size();
        var buffer = try allocator.alloc(u8, total_size);

        var header_bytes: [88]u8 = undefined;
        self.header.toBytes(&header_bytes);
        @memcpy(buffer[0..88], &header_bytes);

        @memcpy(buffer[88 .. 88 + self.payload.len], self.payload);

        var trailer_bytes: [36]u8 = undefined;
        self.trailer.toBytes(&trailer_bytes);
        const trailer_start = 88 + self.payload.len;
        @memcpy(buffer[trailer_start .. trailer_start + 36], &trailer_bytes);

        return buffer;
    }

    pub fn decode(allocator: std.mem.Allocator, data: []const u8) !LWFFrame {
        if (data.len < 88 + 36) return error.FrameTooSmall;

        var header_bytes: [88]u8 = undefined;
        @memcpy(&header_bytes, data[0..88]);
        const header = LWFHeader.fromBytes(&header_bytes);

        if (!header.isValid()) return error.InvalidHeader;

        const payload_len = @as(usize, @intCast(header.payload_len));
        if (data.len < 88 + payload_len + 36) return error.InvalidPayloadLength;

        const payload = try allocator.alloc(u8, payload_len);
        @memcpy(payload, data[88 .. 88 + payload_len]);

        const trailer_start = 88 + payload_len;
        var trailer_bytes: [36]u8 = undefined;
        @memcpy(&trailer_bytes, data[trailer_start .. trailer_start + 36]);
        const trailer = LWFTrailer.fromBytes(&trailer_bytes);

        return .{
            .header = header,
            .payload = payload,
            .trailer = trailer,
        };
    }

    pub fn calculateChecksum(self: *const LWFFrame) u32 {
        var hasher = std.hash.Crc32.init();
        var header_bytes: [88]u8 = undefined;
        self.header.toBytes(&header_bytes);
        hasher.update(&header_bytes);
        hasher.update(self.payload);
        return hasher.final();
    }

    pub fn verifyChecksum(self: *const LWFFrame) bool {
        const computed = self.calculateChecksum();
        const stored = std.mem.bigToNative(u32, self.trailer.checksum);
        return computed == stored;
    }

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

    try std.testing.expectEqual(@as(usize, 88 + 100 + 36), frame.size());
    try std.testing.expectEqual(@as(u8, 'L'), frame.header.magic[0]);
    try std.testing.expectEqual(@as(u8, 0x02), frame.header.version);
}

test "LWFFrame encode/decode roundtrip" {
    const allocator = std.testing.allocator;
    var frame = try LWFFrame.init(allocator, 10);
    defer frame.deinit(allocator);

    frame.header.service_type = 0x0A00;
    frame.header.payload_len = 10;
    frame.header.timestamp = 1234567890;
    // Set a session ID
    frame.header.session_id = [_]u8{0xEE} ** 16;

    @memcpy(frame.payload, "HelloWorld");
    frame.updateChecksum();

    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    try std.testing.expectEqual(@as(usize, 88 + 10 + 36), encoded.len);

    var decoded = try LWFFrame.decode(allocator, encoded);
    defer decoded.deinit(allocator);

    try std.testing.expectEqualSlices(u8, "HelloWorld", decoded.payload);
    try std.testing.expectEqual(frame.header.service_type, decoded.header.service_type);
    try std.testing.expectEqualSlices(u8, &frame.header.session_id, &decoded.header.session_id);
}

test "FrameClass payload sizes" {
    // Overhead = 88 + 36 = 124
    // Micro: 128 - 124 = 4 bytes remaining
    try std.testing.expectEqual(@as(usize, 4), FrameClass.micro.maxPayloadSize());
    // Mini: 512 - 124 = 388
    try std.testing.expectEqual(@as(usize, 388), FrameClass.mini.maxPayloadSize());
    // Big: 4096 - 124 = 3972
    try std.testing.expectEqual(@as(usize, 3972), FrameClass.big.maxPayloadSize());
}
