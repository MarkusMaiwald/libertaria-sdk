const std = @import("std");
const png = @import("png.zig");

pub const TransportSkin = union(enum) {
    raw: RawSkin,
    mimic_https: MimicHttpsSkin,
    
    const Self = @This();
    
    pub fn init(config: SkinConfig) !Self {
        return switch (config.skin_type) {
            .Raw => Self{ .raw = try RawSkin.init(config) },
            .MimicHttps => Self{ .mimic_https = try MimicHttpsSkin.init(config) },
        };
    }
    
    pub fn deinit(self: *Self) void {
        switch (self.*) {
            .raw => |*skin| skin.deinit(),
            .mimic_https => |*skin| skin.deinit(),
        }
    }
    
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.wrap(allocator, lwf_frame),
            .mimic_https => |*skin| skin.wrap(allocator, lwf_frame),
        };
    }
    
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        return switch (self.*) {
            .raw => |*skin| skin.unwrap(allocator, wire_data),
            .mimic_https => |*skin| skin.unwrap(allocator, wire_data),
        };
    }
    
    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .raw => "RAW",
            .mimic_https => "MIMIC_HTTPS",
        };
    }
    
    pub fn overheadEstimate(self: Self) f64 {
        return switch (self) {
            .raw => 0.0,
            .mimic_https => 0.05,
        };
    }
};

pub const SkinConfig = struct {
    skin_type: SkinType,
    allocator: std.mem.Allocator,
    cover_domain: ?[]const u8 = null,
    real_endpoint: ?[]const u8 = null,
    ws_path: ?[]const u8 = null,
    png_state: ?png.PngState = null,
    
    pub const SkinType = enum {
        Raw,
        MimicHttps,
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
    cover_domain: []const u8,
    real_endpoint: []const u8,
    ws_path: []const u8,
    png_state: ?png.PngState,
    
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
    
    pub fn deinit(_: *Self) void {}
    
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        _ = self;
        // Simplified - just return copy for now
        return try allocator.dupe(u8, lwf_frame);
    }
    
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        _ = self;
        return try allocator.dupe(u8, wire_data);
    }
};

test "RawSkin basic" {
    const allocator = std.testing.allocator;
    var skin = try RawSkin.init(.{ .skin_type = .Raw, .allocator = allocator });
    defer skin.deinit();
    
    const lwf = "test";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    try std.testing.expectEqualStrings(lwf, wrapped);
}
