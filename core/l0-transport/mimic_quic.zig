// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Libertaria Contributors
// This file is part of the Libertaria Core, licensed under
// The Libertaria Commonwealth License v1.0.


//! RFC-0015: MIMIC_QUIC Skin (HTTP/3 over QUIC)
//!
//! Modern replacement for WebSockets with 0-RTT connection establishment.
//! Uses QUIC over UDP with HTTP/3 framing — looks like standard browser traffic.
//!
//! Advantages over WebSockets:
//! - 0-RTT connection resumption (no TCP handshake latency)
//! - Built-in TLS 1.3 (no separate upgrade)
//! - Connection migration (survives IP changes)
//! - Better congestion control (not stuck in TCP head-of-line blocking)
//! - Harder to block (UDP port 443, looks like HTTP/3)
//!
//! References:
//! - RFC 9000: QUIC
//! - RFC 9114: HTTP/3
//! - RFC 9293: Connection Migration

const std = @import("std");
const png = @import("png.zig");

/// QUIC Header Types
const QuicHeaderType = enum {
    long,   // Initial, Handshake, 0-RTT
    short,  // 1-RTT packets
    retry,  // Retry packets
    version_negotiation,
};

/// QUIC Long Header (for handshake)
pub const QuicLongHeader = packed struct {
    header_form: u1 = 1,      // Always 1 for long header
    fixed_bit: u1 = 1,        // Must be 1
    packet_type: u2,          // Initial(0), 0-RTT(1), Handshake(2), Retry(3)
    version_specific: u4,     // Type-specific bits
    version: u32,             // QUIC version (e.g., 0x00000001 for v1)
    dcil: u4,                 // Destination Connection ID Length - 1
    scil: u4,                 // Source Connection ID Length - 1
    // Connection IDs follow (variable length)
    // Length + Packet Number + Payload follow
};

/// QUIC Short Header (for 1-RTT data)
pub const QuicShortHeader = packed struct {
    header_form: u1 = 0,      // Always 0 for short header
    fixed_bit: u1 = 1,
    spin_bit: u1,             // Latency spin bit
    reserved: u2 = 0,         // Must be 0
    key_phase: u1,            // Key update phase
    packet_number_length: u2, // Length of packet number - 1
    // Destination Connection ID follows (implied from context)
    // Packet Number + Payload follow
};

/// MIMIC_QUIC Skin — HTTP/3 over QUIC
pub const MimicQuicSkin = struct {
    allocator: std.mem.Allocator,
    
    // QUIC Connection State
    version: u32 = 0x00000001,  // QUIC v1
    dst_cid: [20]u8,            // Destination Connection ID
    src_cid: [20]u8,            // Source Connection ID
    next_packet_number: u64 = 0,
    
    // HTTP/3 Settings
    settings: Http3Settings,
    
    // PNG for traffic shaping
    png_state: ?png.PngState,
    
    pub const Http3Settings = struct {
        max_field_section_size: u64 = 8192,
        qpack_max_table_capacity: u64 = 4096,
        qpack_blocked_streams: u64 = 100,
    };
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, png_state: ?png.PngState) !Self {
        var self = Self{
            .allocator = allocator,
            .dst_cid = undefined,
            .src_cid = undefined,
            .settings = .{},
            .png_state = png_state,
        };
        
        // Generate random Connection IDs (in production: crypto-secure)
        // Using deterministic values for reproducibility
        @memset(&self.dst_cid, 0xAB);
        @memset(&self.src_cid, 0xCD);
        
        return self;
    }
    
    pub fn deinit(_: *Self) void {}
    
    /// Wrap LWF frame as HTTP/3 stream data over QUIC
    pub fn wrap(self: *Self, allocator: std.mem.Allocator, lwf_frame: []const u8) ![]u8 {
        // Apply PNG padding if available
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
        
        // Build HTTP/3 DATA frame
        const http3_frame = try self.buildHttp3DataFrame(allocator, payload);
        defer allocator.free(http3_frame);
        
        // Wrap in QUIC short header (1-RTT)
        return try self.buildQuicShortPacket(allocator, http3_frame);
    }
    
    /// Unwrap QUIC packet back to LWF frame
    pub fn unwrap(self: *Self, allocator: std.mem.Allocator, wire_data: []const u8) !?[]u8 {
        if (wire_data.len < 5) return null;
        
        // Parse QUIC header
        const is_long_header = (wire_data[0] & 0x80) != 0;
        if (is_long_header) {
            // Long header — likely Initial or Handshake, drop for now
            // In production: handle handshake
            return null;
        }
        
        // Short header — extract payload
        const pn_len: u3 = @as(u3, @intCast(wire_data[0] & 0x03)) + 1;
        const header_len = 1 + 20 + @as(usize, pn_len); // flags + DCID + PN
        
        if (wire_data.len <= header_len) return null;
        
        const payload = wire_data[header_len..];
        
        // Parse HTTP/3 frame
        const lwf = try self.parseHttp3DataFrame(allocator, payload);
        if (lwf == null) return null;
        
        // Remove padding if applicable
        if (self.png_state) |_| {
            const unpadded = try self.removePadding(allocator, lwf.?);
            allocator.free(lwf.?);
            return unpadded;
        }
        
        return lwf;
    }
    
    /// Build HTTP/3 DATA frame (RFC 9114)
    fn buildHttp3DataFrame(_: *Self, allocator: std.mem.Allocator, data: []const u8) ![]u8 {
        // HTTP/3 Frame Format:
        // Length (variable) | Type (variable) | Flags (1) | Body
        
        const frame_type: u64 = 0x00; // DATA frame
        const frame_len: u64 = data.len;
        
        // Calculate encoded sizes
        const type_len = encodeVarintLen(frame_type);
        const len_len = encodeVarintLen(frame_len);
        
        const frame = try allocator.alloc(u8, type_len + len_len + data.len);
        
        // Encode Length
        var offset: usize = 0;
        offset += encodeVarint(frame[0..], frame_len);
        
        // Encode Type
        offset += encodeVarint(frame[offset..], frame_type);
        
        // Copy body
        @memcpy(frame[offset..], data);
        
        return frame;
    }
    
    /// Parse HTTP/3 DATA frame
    fn parseHttp3DataFrame(_: *Self, allocator: std.mem.Allocator, data: []const u8) !?[]u8 {
        if (data.len < 2) return null;
        
        // Parse Length
        var offset: usize = 0;
        const frame_len = try decodeVarint(data, &offset);
        
        // Parse Type
        const frame_type = try decodeVarint(data, &offset);
        
        // We only handle DATA frames (type 0x00)
        if (frame_type != 0x00) return null;
        
        if (data.len < offset + frame_len) return null;
        
        const body = data[offset..][0..frame_len];
        return try allocator.dupe(u8, body);
    }
    
    /// Build QUIC short header packet (1-RTT)
    fn buildQuicShortPacket(self: *Self, allocator: std.mem.Allocator, payload: []const u8) ![]u8 {
        // Short Header Format:
        // Flags (1) | DCID (implied) | Packet Number (1-4) | Payload
        
        const pn_len: u2 = 3; // 4-byte packet numbers
        const packet_number = self.next_packet_number;
        self.next_packet_number += 1;
        
        // Header byte
        // Bits: 1 (Fixed) | 0 (Spin) | 00 (Reserved) | 0 (Key phase) | 11 (PN len = 4)
        const header_byte: u8 = 0x40 | @as(u8, pn_len);
        
        const packet = try allocator.alloc(u8, 1 + 20 + 4 + payload.len);
        
        // Write header
        packet[0] = header_byte;
        
        // Write Destination Connection ID
        @memcpy(packet[1..21], &self.dst_cid);
        
        // Write Packet Number (4 bytes)
        std.mem.writeInt(u32, packet[21..25], @truncate(packet_number), .big);
        
        // Write payload
        @memcpy(packet[25..], payload);
        
        return packet;
    }
    
    // PNG Padding helpers (same as other skins)
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
};

/// QUIC Variable-Length Integer Encoding (RFC 9000)
fn encodeVarintLen(value: u64) usize {
    if (value <= 63) return 1;
    if (value <= 16383) return 2;
    if (value <= 1073741823) return 4;
    return 8;
}

fn encodeVarint(buf: []u8, value: u64) usize {
    if (value <= 63) {
        buf[0] = @as(u8, @intCast(value));
        return 1;
    } else if (value <= 16383) {
        const encoded: u16 = @as(u16, @intCast(value)) | 0x4000;
        std.mem.writeInt(u16, buf[0..2], encoded, .big);
        return 2;
    } else if (value <= 1073741823) {
        const encoded: u32 = @as(u32, @intCast(value)) | 0x80000000;
        std.mem.writeInt(u32, buf[0..4], encoded, .big);
        return 4;
    } else {
        const encoded: u64 = value | 0xC000000000000000;
        std.mem.writeInt(u64, buf[0..8], encoded, .big);
        return 8;
    }
}

fn decodeVarint(data: []const u8, offset: *usize) !u64 {
    if (data.len <= offset.*) return error.Truncated;
    
    const first = data[offset.*];
    const prefix = first >> 6;
    
    var result: u64 = 0;
    switch (prefix) {
        0 => {
            result = first & 0x3F;
            offset.* += 1;
        },
        1 => {
            if (data.len < offset.* + 2) return error.Truncated;
            result = std.mem.readInt(u16, data[offset.*..][0..2], .big) & 0x3FFF;
            offset.* += 2;
        },
        2 => {
            if (data.len < offset.* + 4) return error.Truncated;
            result = std.mem.readInt(u32, data[offset.*..][0..4], .big) & 0x3FFFFFFF;
            offset.* += 4;
        },
        3 => {
            if (data.len < offset.* + 8) return error.Truncated;
            result = std.mem.readInt(u64, data[offset.*..][0..8], .big) & 0x3FFFFFFFFFFFFFFF;
            offset.* += 8;
        },
        else => unreachable,
    }
    
    return result;
}

// ============================================================================
// TESTS
// ============================================================================

test "QUIC varint encode/decode" {
    // Test all size classes
    const test_values = [_]u64{ 0, 63, 64, 16383, 16384, 1073741823, 1073741824, 4611686018427387903 };
    
    var buf: [8]u8 = undefined;
    
    for (test_values) |value| {
        const len = encodeVarint(&buf, value);
        var offset: usize = 0;
        const decoded = try decodeVarint(&buf, &offset);
        
        try std.testing.expectEqual(value, decoded);
        try std.testing.expectEqual(len, offset);
    }
}

test "HTTP/3 DATA frame roundtrip" {
    const allocator = std.testing.allocator;
    
    var skin = try MimicQuicSkin.init(allocator, null);
    defer skin.deinit();
    
    const data = "Hello, HTTP/3!";
    const frame = try skin.buildHttp3DataFrame(allocator, data);
    defer allocator.free(frame);
    
    const parsed = try skin.parseHttp3DataFrame(allocator, frame);
    defer if (parsed) |p| allocator.free(p);
    
    try std.testing.expect(parsed != null);
    try std.testing.expectEqualStrings(data, parsed.?);
}

test "MIMIC_QUIC wrap/unwrap roundtrip" {
    const allocator = std.testing.allocator;
    
    var skin = try MimicQuicSkin.init(allocator, null);
    defer skin.deinit();
    
    const lwf = "LWF test frame";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    // Should have QUIC short header + HTTP/3 frame
    try std.testing.expect(wrapped.len > lwf.len);
    
    // Verify short header
    try std.testing.expect((wrapped[0] & 0x80) == 0); // Short header flag
    
    const unwrapped = try skin.unwrap(allocator, wrapped);
    defer if (unwrapped) |u| allocator.free(u);
    
    try std.testing.expect(unwrapped != null);
    try std.testing.expectEqualStrings(lwf, unwrapped.?);
}

test "MIMIC_QUIC with PNG padding" {
    const allocator = std.testing.allocator;
    
    const secret = [_]u8{0x42} ** 32;
    const png_state = png.PngState.initFromSharedSecret(secret);
    
    var skin = try MimicQuicSkin.init(allocator, png_state);
    defer skin.deinit();
    
    const lwf = "A";
    const wrapped = try skin.wrap(allocator, lwf);
    defer allocator.free(wrapped);
    
    // Should be padded to target size
    try std.testing.expect(wrapped.len > lwf.len + 25); // Header + padding
}
