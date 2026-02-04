const std = @import("std");
const png = @import("png.zig");
const mimic_dns = @import("mimic_dns.zig");
const mimic_https = @import("mimic_https.zig");

pub const TransportSkin = union(enum) {
    raw: RawSkin,
    mimic_https: MimicHttpsSkin,
    mimic_dns: mimic_dns.MimicDnsSkin,
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return switch (config.skin_type) {
            .Raw => Self{ .raw = try RawSkin.init(config) },
            .MimicHttps => Self{ .mimic_https = try MimicHttpsSkin.init(config) },
            .MimicDns => Self{ .mimic_dns = try mimic_dns.MimicDnsSkin.init(
                mimic_dns.SkinConfig{
                    .allocator = config.allocator,
                    .doh_endpoint = config.doh_endpoint,
                    .cover_resolver = config.cover_resolver,
                    .png_state = config.png_state,
                }
            )},
        };
    }
    
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .raw => |*skin| skin.deinit(),
            .mimic_https => |*skin| skin.deinit(),
            .mimic_dns => |*skin| skin.deinit(),
        }
    }
    
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.wrap(allocator, lwf_frame),
            .mimic_https => |*skin| skin.wrap(allocator, lwf_frame),
            .mimic_dns => |*skin| skin.wrap(allocator, lwf_frame),
        };
    }
    
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.unwrap(allocator, wire_data),
            .mimic_https => |*skin| skin.unwrap(allocator, wire_data),
            .mimic_dns => |*skin| skin.unwrap(allocator, wire_data),
        };
    }
    
    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .raw => "RAW",
            .mimic_https => "MIMIC_HTTPS",
            .mimic_dns => "MIMIC_DNS",
        };
    }
    
    pub fn overheadEstimate(self: Self) f64 {
        return switch (self) {
            .raw => 0.0,
            .mimic_https => 0.05,
            .mimic_dns => 0.15, // Higher overhead due to encoding
        };
    }
};

pub const SkinConfig = struct {
    allocator: std.mem.Allocator,
    skin_type: SkinType,
    cover_domain: ?[]const u8 = null,
    real_endpoint: ?[]const u8 = null,
    ws_path: ?[]const u8 = null,
    doh_endpoint: ?[]const u8 = null,
    cover_resolver: ?[]const u8 = null,
    png_state: ?png.PngState = null,
    
    pub const SkinType = enum {
        Raw,
        MimicHttps,
        MimicDns,
    };
};

pub const RawSkin = struct {
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return Self{ .allocator = config.allocator };
    }
    
    pub fn deinit(_: *Self) void {}
    
    pub fn wrap(_: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        return try allocator.dupe(u8, lwf_frame);
    }
    
    pub fn unwrap(_: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        return try allocator.dupe(u8, wire_data);
    }
};

pub const MimicHttpsSkin = struct {
    allocator: std.mem.Allocator,
    config: mimic_https.MimicHttpsConfig,
    png_state: ?png.PngState,
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return Self{
            .allocator = config.allocator,
            .config = mimic_https.MimicHttpsConfig{
                .cover_domain = config.cover_domain orelse "cdn.cloudflare.com",
                .real_endpoint = config.real_endpoint orelse "relay.libertaria.network",
                .ws_path = config.ws_path orelse "/api/v1/stream",
            },
            .png_state = config.png_state,
        };
    }
    
    pub fn deinit(_: *Self) void {}
    
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        // Apply PNG padding first
        var payload = lwf_frame;
        var padded: ?[]u8 = null;
        
        if (self.png_state) |*png_state| {
            const target_size = png_state.samplePacketSize();
            if (target_size > lwf_frame.len) {
                padded = try self.addPadding(allocator, lwf_frame, target_size);
                payload = padded.?;
            }
            png_state.advancePacket();
        }
        defer if (padded) |p| allocator.free(p);
        
        // Generate random mask key
        var mask_key: [4]u8 = undefined;
        // In production: crypto-secure random
        mask_key = [4]u8{ 0x12, 0x34, 0x56, 0x78 };
        
        // Build WebSocket frame
        const frame = mimic_https.WebSocketFrame{
            .fin = true,
            .opcode = .binary,
            .masked = true,
            .payload = payload,
            .mask_key = mask_key,
        };
        
        return try frame.encode(allocator);
    }
    
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        const frame = try mimic_https.WebSocketFrame.decode(allocator, wire_data);
        defer if (frame) |f| allocator.free(f.payload);
        
        if (frame == null) return null;
        
        const payload = frame.?.payload;
        
        // Remove PNG padding if applicable
        if (self.png_state) |_| {
            const unpadded = try self.removePadding(allocator, payload);
            allocator.free(payload);
            return unpadded;
        }
        
        return try allocator.dupe(u8, payload);
    }
    
    fn addPadding(_: *Self, allocator: std.mem.Allocator, data: []const u8, target_size: u16) ![]u8 {
        if (target_size <= data.len) return try allocator.dupe(u8, data);
        
        const padded = try allocator.alloc(u8, target_size);
        std.mem.writeInt(u16, padded[0..2], @as(u16, @intCast(data.len)), .big);
        @memcpy(padded[2..][0..data.len], data);
        
        var i: usize = 2 + data.len;
        while (i < target_size) : (i += 1) {
            padded[i] = @as(u8, @truncate(i * 7));
        }
        
        return padded;
    }
    
    fn removePadding(_: *Self, allocator: std.mem.Allocator, padded: []const u8) ![]u8 {
        if (padded.len < 2) return try allocator.dupe(u8, padded);
        
        const original_len = std.mem.readInt(u16, padded[0..2], .big);
        if (original_len > padded.len - 2) return try allocator.dupe(u8, padded);
        
        const result = try allocator.alloc(u8, original_len);
        @memcpy(result, padded[2..][0..original_len]);
        return result;
    }
    
    /// Build domain fronting HTTP upgrade request
    pub fn buildUpgradeRequest(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const request = mimic_https.DomainFrontingRequest{
            .cover_domain = self.config.cover_domain,
            .real_host = self.config.real_endpoint,
            .path = self.config.ws_path,
            .user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        };
        return try request.build(allocator);
    }
};

test "RawSkin basic" {
    const allocator = std.testing.allocator;
    var skin = try RawSkin.init(.{ .allocator = allocator, .skin_type = .Raw });
    defer skin.deinit();
    
    const lwf = "test";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    try std.testing.expectEqualStrings(lwf, wrapped);
}

test "MimicHttpsSkin basic" {
    const allocator = std.testing.allocator;
    var skin = try MimicHttpsSkin.init(.{ .allocator = allocator, .skin_type = .MimicHttps });
    defer skin.deinit();
    
    const lwf = "test";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    try std.testing.expect(wrapped.len >= lwf.len);
}

test "TransportSkin union dispatch" {
    const allocator = std.testing.allocator;
    
    // Test RAW
    var raw_skin = try TransportSkin.init(.{ .allocator = allocator, .skin_type = .Raw });
    defer raw_skin.deinit();
    try std.testing.expectEqualStrings("RAW", raw_skin.name());
    
    // Test MIMIC_HTTPS
    var https_skin = try TransportSkin.init(.{ .allocator = allocator, .skin_type = .MimicHttps });
    defer https_skin.deinit();
    try std.testing.expectEqualStrings("MIMIC_HTTPS", https_skin.name());
}
