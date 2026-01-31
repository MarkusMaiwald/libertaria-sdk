//! RFC-0018: Bridge Protocol (Layer 3)
//!
//! Bridges translate between:
//! 1. Different Libertaria protocol versions
//! 2. Legacy protocols (HTTP, SMTP, DNS)
//! 3. Cross-Chapter communication
//!
//! Bridges are Chapter-scoped and governance-controlled.

const std = @import("std");
const net = std.net;

pub const BridgeError = error{
    UnsupportedProtocol,
    TranslationFailed,
    ChapterMismatch,
    InvalidDIDMapping,
    ProtocolVersionMismatch,
};

/// Protocol types that bridges can translate
pub const ProtocolType = enum {
    Libertaria_V1,
    Libertaria_V2,
    HTTP_1_1,
    HTTP_2,
    SMTP,
    DNS,
    Nostr,
};

/// Direction of bridge translation
pub const BridgeDirection = enum {
    Inbound, // Legacy → Libertaria
    Outbound, // Libertaria → Legacy
};

/// Chapter identifier (32-byte hash of Chapter governance key)
pub const ChapterID = [32]u8;

/// DID mapping for cross-Chapter translation
pub const DIDMapping = struct {
    local_did: [32]u8,
    remote_did: [32]u8,
    chapter_id: ChapterID,
};

/// Bridge state tracking
pub const BridgeStats = struct {
    packets_translated: u64,
    translation_errors: u64,
    last_activity_ms: i64,
    reputation_score: f64,
};

/// Main Bridge structure
pub const ChapterBridge = struct {
    allocator: std.mem.Allocator,
    local_chapter: ChapterID,
    remote_chapter: ?ChapterID, // null for legacy protocol bridges
    protocol_type: ProtocolType,

    // DID translation table (for cross-Chapter bridges)
    did_mappings: std.AutoHashMap([32]u8, DIDMapping),

    // Stats
    stats: BridgeStats,

    pub fn init(
        allocator: std.mem.Allocator,
        local_chapter: ChapterID,
        protocol_type: ProtocolType,
    ) ChapterBridge {
        return .{
            .allocator = allocator,
            .local_chapter = local_chapter,
            .remote_chapter = null,
            .protocol_type = protocol_type,
            .did_mappings = std.AutoHashMap([32]u8, DIDMapping).init(allocator),
            .stats = .{
                .packets_translated = 0,
                .translation_errors = 0,
                .last_activity_ms = std.time.milliTimestamp(),
                .reputation_score = 1.0,
            },
        };
    }

    pub fn deinit(self: *ChapterBridge) void {
        self.did_mappings.deinit();
    }

    /// Register a DID mapping for cross-Chapter communication
    pub fn registerDIDMapping(
        self: *ChapterBridge,
        local_did: [32]u8,
        remote_did: [32]u8,
        remote_chapter: ChapterID,
    ) !void {
        const mapping = DIDMapping{
            .local_did = local_did,
            .remote_did = remote_did,
            .chapter_id = remote_chapter,
        };
        try self.did_mappings.put(local_did, mapping);
    }

    /// Translate a DID from local to remote Chapter
    pub fn translateDID(
        self: *ChapterBridge,
        local_did: [32]u8,
        direction: BridgeDirection,
    ) ![32]u8 {
        const mapping = self.did_mappings.get(local_did) orelse return error.InvalidDIDMapping;

        return switch (direction) {
            .Outbound => mapping.remote_did,
            .Inbound => mapping.local_did,
        };
    }

    /// Update bridge statistics
    fn updateStats(self: *ChapterBridge, success: bool) void {
        if (success) {
            self.stats.packets_translated += 1;
        } else {
            self.stats.translation_errors += 1;
            // Degrade reputation on errors
            self.stats.reputation_score *= 0.99;
        }
        self.stats.last_activity_ms = std.time.milliTimestamp();
    }
};

/// HTTP Bridge Adapter
pub const HttpBridge = struct {
    base: ChapterBridge,

    pub fn init(allocator: std.mem.Allocator, local_chapter: ChapterID) HttpBridge {
        return .{
            .base = ChapterBridge.init(allocator, local_chapter, .HTTP_1_1),
        };
    }

    pub fn deinit(self: *HttpBridge) void {
        self.base.deinit();
    }

    /// Translate HTTP request to Libertaria packet
    pub fn translateRequest(
        self: *HttpBridge,
        http_request: []const u8,
        target_did: [32]u8,
    ) ![]u8 {
        _ = target_did;

        // MVP: Parse HTTP headers, extract body
        // Construct LWF frame with HTTP metadata

        // For now, return the request as-is (placeholder)
        // Real implementation would:
        // 1. Parse HTTP method, path, headers
        // 2. Encode into LWF ServiceType.HTTP_BRIDGE
        // 3. Encrypt payload

        const result = try self.base.allocator.dupe(u8, http_request);
        self.base.updateStats(true);
        return result;
    }

    /// Translate Libertaria response to HTTP
    pub fn translateResponse(
        self: *HttpBridge,
        lwf_response: []const u8,
    ) ![]u8 {
        // MVP: Extract LWF payload, wrap in HTTP response format

        const http_header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n";

        var result = try self.base.allocator.alloc(u8, http_header.len + lwf_response.len);
        @memcpy(result[0..http_header.len], http_header);
        @memcpy(result[http_header.len..], lwf_response);

        self.base.updateStats(true);
        return result;
    }
};

/// SMTP Bridge Adapter
pub const SmtpBridge = struct {
    base: ChapterBridge,

    pub fn init(allocator: std.mem.Allocator, local_chapter: ChapterID) SmtpBridge {
        return .{
            .base = ChapterBridge.init(allocator, local_chapter, .SMTP),
        };
    }

    pub fn deinit(self: *SmtpBridge) void {
        self.base.deinit();
    }

    /// Translate SMTP email to Libertaria message
    pub fn translateEmail(
        self: *SmtpBridge,
        email_data: []const u8,
    ) ![]u8 {
        // MVP: Parse SMTP headers (From, To, Subject)
        // Encode into LWF message format

        const result = try self.base.allocator.dupe(u8, email_data);
        self.base.updateStats(true);
        return result;
    }
};

test "Bridge: DID mapping" {
    const allocator = std.testing.allocator;

    const local_chapter = [_]u8{0xAA} ** 32;
    var bridge = ChapterBridge.init(allocator, local_chapter, .Libertaria_V1);
    defer bridge.deinit();

    const local_did = [_]u8{0x11} ** 32;
    const remote_did = [_]u8{0x22} ** 32;
    const remote_chapter = [_]u8{0xBB} ** 32;

    try bridge.registerDIDMapping(local_did, remote_did, remote_chapter);

    const translated = try bridge.translateDID(local_did, .Outbound);
    try std.testing.expectEqualSlices(u8, &remote_did, &translated);
}

test "HttpBridge: Request translation" {
    const allocator = std.testing.allocator;

    const local_chapter = [_]u8{0xAA} ** 32;
    var http_bridge = HttpBridge.init(allocator, local_chapter);
    defer http_bridge.deinit();

    const request = "GET / HTTP/1.1\r\nHost: example.com\r\n\r\n";
    const target_did = [_]u8{0x11} ** 32;

    const result = try http_bridge.translateRequest(request, target_did);
    defer allocator.free(result);

    try std.testing.expect(result.len > 0);
}
