//! RFC-0015: Transport Skins Interface
//!
//! Pluggable censorship-resistant transport layer.
//! Each skin wraps LWF frames to mimic benign traffic patterns.

const std = @import("std");
const png = @import("png.zig");

/// Transport skin interface
/// All skins implement this common API
pub const TransportSkin = union(enum) {
    raw: RawSkin,
    mimic_https: MimicHttpsSkin,
    // mimic_dns: MimicDnsSkin,
    // mimic_video: MimicVideoSkin,
    // stego_image: StegoImageSkin,
    
    const Self = @This();
    
    /// Initialize skin from configuration
    pub fn init(config: SkinConfig) !Self {
        return switch (config.skin_type) {
            .Raw => Self{ .raw = try RawSkin.init(config) },
            .MimicHttps => Self{ .mimic_https = try MimicHttpsSkin.init(config) },
            // .MimicDns => ...
            // .MimicVideo => ...
            // .StegoImage => ...
        };
    }
    
    /// Cleanup skin resources
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            inline else => |*skin| skin.deinit(),
        }
    }
    
    /// Wrap LWF frame for transmission
    /// Returns owned slice (caller must free)
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.wrap(allocator, lwf_frame),
            .mimic_https => |*skin| skin.wrap(allocator, lwf_frame),
        };
    }
    
    /// Unwrap received data to extract LWF frame
    /// Returns owned slice (caller must free)
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.unwrap(allocator, wire_data),
            .mimic_https => |*skin| skin.unwrap(allocator, wire_data),
        };
    }
    
    /// Get skin name for logging/debugging
    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .raw => "RAW",
            .mimic_https => "MIMIC_HTTPS",
            // .mimic_dns => "MIMIC_DNS",
            // .mimic_video => "MIMIC_VIDEO",
            // .stego_image => "STEGO_IMAGE",
        };
    }
    
    /// Get bandwidth overhead estimate (0.0 = 0%, 1.0 = 100%)
    pub fn overheadEstimate(self: Self) f64 {
        return switch (self) {
            .raw => 0.0,
            .mimic_https => 0.05, // ~5% TLS + WS overhead
            // .mimic_dns => 2.0,  // ~200% encoding overhead
            // .mimic_video => 0.10, // ~10% container overhead
            // .stego_image => 10.0, // ~1000% overhead
        };
    }
};

/// Skin configuration
pub const SkinConfig = struct {
    skin_type: SkinType,
    allocator: std.mem.Allocator,
    
    // For MIMIC_HTTPS
    cover_domain: ?[]const u8 = null,      // SNI domain
    real_endpoint: ?[]const u8 = null,     // Actual relay
    ws_path: ?[]const u8 = null,           // WebSocket path
    
    // For PNG (all skins)
    png_state: ?png.PngState = null,
    
    pub const SkinType = enum {
        Raw,
        MimicHttps,
        // MimicDns,
        // MimicVideo,
        // StegoImage,
    };
};

// ============================================================================
// Skin 0: RAW (Unrestricted Networks)
// ============================================================================

pub const RawSkin = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return Self{
            .allocator = config.allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    /// Raw: No wrapping, just copy
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        return try allocator.dupe(u8, lwf_frame);
    }
    
    /// Raw: No unwrapping, just copy
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        _ = self;
        return try allocator.dupe(u8, wire_data);
    }
};

// ============================================================================
// Skin 1: MIMIC_HTTPS (WebSocket over TLS)
// ============================================================================

pub const MimicHttpsSkin = struct {
    allocator: std.mem.Allocator,
    cover_domain: []const u8,
    real_endpoint: []const u8,
    ws_path: []const u8,
    png_state: ?png.PngState,
    
    /// WebSocket frame types
    const WsOpcode = enum(u4) {
        Continuation = 0x0,
        Text = 0x1,
        Binary = 0x2,
        Close = 0x8,
        Ping = 0x9,
        Pong = 0xA,
    };
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return Self{
            .allocator = config.allocator,
            .cover_domain = config.cover_domain orelse "cdn.cloudflare.com",
            .real_endpoint = config.real_endpoint orelse "relay.libertaria.network",
            .ws_path = config.ws_path orelse "/api/v1/stream",
            .png_state = config.png_state,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
    }
    
    /// Wrap LWF frame in WebSocket binary frame with PNG padding
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        // Get target size from PNG (if available)
        var target_size: usize = lwf_frame.len;
        var padding_len: usize = 0;
        
        if (self.png_state) |*png_state| {
            target_size = png_state.samplePacketSize();
            if (target_size > lwf_frame.len + 14) { // 14 = WebSocket header max
                padding_len = target_size - lwf_frame.len - 14;
            }
            png_state.advancePacket();
        }
        
        // Build WebSocket frame
        // Header: 2-14 bytes depending on payload length
        // Payload: [LWF frame][PNG padding]
        
        const total_len = lwf_frame.len + padding_len;
        const frame_size = self.calculateWsFrameSize(total_len);
        
        var frame = try allocator.alloc(u8, frame_size);
        errdefer allocator.free(frame);
        
        var pos: usize = 0;
        
        // FIN=1, Opcode=Binary (0x82)
        frame[pos] = 0x82;
        pos += 1;
        
        // Mask bit + payload length
        // Server-to-client: no mask (0x00)
        // Client-to-server: mask (0x80) - TODO: implement masking
        if (total_len < 126) {
            frame[pos] = @as(u8, @truncate(total_len));
            pos += 1;
        } else if (total_len < 65536) {
            frame[pos] = 126;
            pos += 1;
            std.mem.writeInt(u16, frame[pos..][0..2], @as(u16, @truncate(total_len)), .big);
            pos += 2;
        } else {
            frame[pos] = 127;
            pos += 1;
            std.mem.writeInt(u64, frame[pos..][0..8], total_len, .big);
            pos += 8;
        }
        
        // Payload: LWF frame + padding
        @memcpy(frame[pos..][0..lwf_frame.len], lwf_frame);
        pos += lwf_frame.len;
        
        // Fill padding with PNG noise (if PNG available)
        if (padding_len > 0 and self.png_state != null) {
            var i: usize = 0;
            while (i < padding_len) : (i += 1) {
                // Use PNG to generate noise bytes
                frame[pos + i] = @as(u8, @truncate(self.png_state.?.nextU64()));
            }
        }
        
        return frame;
    }
    
    /// Unwrap WebSocket frame to extract LWF frame
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        if (wire_data.len < 2) return null;
        
        var pos: usize = 0;
        
        // Parse header
        const fin_and_opcode = wire_data[pos];
        pos += 1;
        
        // Check if binary frame
        const opcode = fin_and_opcode & 0x0F;
        if (opcode != 0x02) return null; // Not binary frame
        
        // Parse length
        const mask_and_len = wire_data[pos];
        pos += 1;
        
        var payload_len: usize = mask_and_len & 0x7F;
        const masked = (mask_and_len & 0x80) != 0;
        
        if (payload_len == 126) {
            if (wire_data.len < pos + 2) return null;
            payload_len = std.mem.readInt(u16, wire_data[pos..][0..2], .big);
            pos += 2;
        } else if (payload_len == 127) {
            if (wire_data.len < pos + 8) return null;
            payload_len = std.mem.readInt(u64, wire_data[pos..][0..8], .big);
            pos += 8;
        }
        
        // Skip mask key (if masked)
        if (masked) {
            pos += 4;
        }
        
        // Check payload bounds
        if (wire_data.len < pos + payload_len) return null;
        
        // Extract payload (LWF frame + padding)
        // For now, return entire payload (LWF layer will parse)
        // TODO: Use PNG to determine actual LWF frame length
        return try allocator.dupe(u8, wire_data[pos..][0..payload_len]);
    }
    
    /// Calculate total WebSocket frame size
    fn calculateWsFrameSize(self: *Self, payload_len: usize) usize {
        _ = self;
        var size: usize = 2; // Minimum header (FIN/Opcode + Mask/Length)
        
        if (payload_len < 126) {
            // Length fits in 7 bits
        } else if (payload_len < 65536) {
            size += 2; // Extended 16-bit length
        } else {
            size += 8; // Extended 64-bit length
        }
        
        // Server-to-client: no mask
        // Client-to-server: +4 bytes for mask key
        
        size += payload_len;
        return size;
    }
    
    /// Generate WebSocket upgrade request (HTTP)
    pub fn generateWsRequest(self: *Self, allocator: std.mem.Allocator, sec_websocket_key: []const u8) ![]u8 {
        return try std.fmt.allocPrint(allocator,
            "GET {s} HTTP/1.1\r\n" ++
            "Host: {s}\r\n" ++
            "Upgrade: websocket\r\n" ++
            "Connection: Upgrade\r\n" ++
            "Sec-WebSocket-Key: {s}\r\n" ++
            "Sec-WebSocket-Version: 13\r\n" ++
            "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\r\n" ++
            "\r\n",
            .{ self.ws_path, self.real_endpoint, sec_websocket_key }
        );
    }
};

// ============================================================================
// Skin Auto-Detection
// ============================================================================

/// Probe sequence for automatic skin selection
pub const SkinProber = struct {
    allocator: std.mem.Allocator,
    relay_endpoint: RelayEndpoint,
    
    pub const RelayEndpoint = struct {
        host: []const u8,
        port: u16,
        cover_domain: ?[]const u8 = null,
    };
    
    pub fn init(allocator: std.mem.Allocator, endpoint: RelayEndpoint) SkinProber {
        return .{
            .allocator = allocator,
            .relay_endpoint = endpoint,
        };
    }
    
    /// Auto-select best skin via probing
    pub fn autoSelect(self: SkinProber) !TransportSkin {
        // 1. Try RAW UDP (100ms timeout)
        if (try self.probeRaw(100)) {
            return TransportSkin.init(.{
                .skin_type = .Raw,
                .allocator = self.allocator,
            });
        }
        
        // 2. Try HTTPS WebSocket (500ms timeout)
        if (try self.probeHttps(500)) {
            return TransportSkin.init(.{
                .skin_type = .MimicHttps,
                .allocator = self.allocator,
                .cover_domain = self.relay_endpoint.cover_domain,
                .real_endpoint = self.relay_endpoint.host,
            });
        }
        
        // 3. Fallback to HTTPS anyway (most reliable)
        return TransportSkin.init(.{
            .skin_type = .MimicHttps,
            .allocator = self.allocator,
            .cover_domain = self.relay_endpoint.cover_domain,
            .real_endpoint = self.relay_endpoint.host,
        });
    }
    
    fn probeRaw(self: SkinProber, timeout_ms: u32) !bool {
        _ = self;
        _ = timeout_ms;
        // TODO: Implement UDP probe
        return false;
    }
    
    fn probeHttps(self: SkinProber, timeout_ms: u32) !bool {
        _ = self;
        _ = timeout_ms;
        // TODO: Implement HTTPS probe
        return true; // Assume HTTPS works for now
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "RawSkin wrap/unwrap" {
    const allocator = std.testing.allocator;
    
    var skin = try RawSkin.init(.{
        .skin_type = .Raw,
        .allocator = allocator,
    });
    defer skin.deinit();
    
    const lwf = "Hello LWF";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    const unwrapped = try skin.unwrap(allocator, wrapped);
    defer allocator.free(unwrapped.?);
    
    try std.testing.expectEqualStrings(lwf, unwrapped.?);
}

test "MimicHttpsSkin WebSocket frame structure" {
    const allocator = std.testing.allocator;
    
    var skin = try MimicHttpsSkin.init(.{
        .skin_type = .MimicHttps,
        .allocator = allocator,
        .cover_domain = "cdn.example.com",
        .real_endpoint = "relay.example.com",
        .ws_path = "/stream",
    });
    defer skin.deinit();
    
    const lwf = [_]u8{0x4C, 0x57, 0x46, 0x00}; // "LWF\0"
    const wrapped = try skin.wrap(allocator, &lwf);
    defer allocator.free(wrapped);
    
    // Check WebSocket frame header
    try std.testing.expectEqual(@as(u8, 0x82), wrapped[0]); // FIN=1, Binary
    try std.testing.expect(wrapped.len >= 2 + lwf.len);
    
    // Verify unwrap returns payload
    const unwrapped = try skin.unwrap(allocator, wrapped);
    defer allocator.free(unwrapped.?);
    
    try std.testing.expectEqualSlices(u8, &lwf, unwrapped.?[0..lwf.len]);
}

test "TransportSkin union dispatch" {
    const allocator = std.testing.allocator;
    
    var skin = try TransportSkin.init(.{
        .skin_type = .Raw,
        .allocator = allocator,
    });
    defer skin.deinit();
    
    const lwf = "Test";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    try std.testing.expectEqualStrings("RAW", skin.name());
    try std.testing.expectEqual(@as(f64, 0.0), skin.overheadEstimate());
}
