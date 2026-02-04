//! L4 Feed — Temporal Event Store
//!
//! Hybrid storage: DuckDB (structured) + LanceDB (vectors)
//! For social media primitives: posts, reactions, follows

const std = @import("std");

/// Event types in the feed
pub const EventType = enum {
    post,           // Content creation
    reaction,       // Like, boost, etc.
    follow,         // Social graph edge
    mention,        // @username reference
    hashtag,        // #topic categorization
};

/// Feed event structure
pub const FeedEvent = struct {
    id: u64,                    // Snowflake ID (time-sortable)
    event_type: EventType,
    author: [32]u8,             // DID of creator
    timestamp: i64,             // Unix nanoseconds
    content_hash: [32]u8,       // Blake3 of content
    parent_id: ?u64,            // For replies/reactions
    
    // Vector embedding for semantic search
    embedding: ?[384]f32,       // 384-dim (optimal for LanceDB)
    
    // Metadata
    tags: []const []const u8,   // Hashtags
    mentions: []const [32]u8,   // Tagged users
    
    pub fn encode(self: FeedEvent, allocator: std.mem.Allocator) ![]u8 {
        // Simple binary encoding
        var result = std.ArrayList(u8).init(allocator);
        errdefer result.deinit();
        
        try result.writer().writeInt(u64, self.id, .little);
        try result.writer().writeInt(u8, @intFromEnum(self.event_type), .little);
        try result.writer().writeAll(&self.author);
        try result.writer().writeInt(i64, self.timestamp, .little);
        try result.writer().writeAll(&self.content_hash);
        
        return result.toOwnedSlice();
    }
};

/// Feed query options
pub const FeedQuery = struct {
    author: ?[32]u8 = null,
    event_type: ?EventType = null,
    since: ?i64 = null,
    until: ?i64 = null,
    tags: ?[]const []const u8 = null,
    limit: usize = 50,
    offset: usize = 0,
};

/// Hybrid feed storage
pub const FeedStore = struct {
    allocator: std.mem.Allocator,
    // TODO: DuckDB connection
    // TODO: LanceDB connection
    
    const Self = @This();
    
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        _ = path;
        // TODO: Initialize DuckDB + LanceDB
        return Self{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        _ = self;
        // TODO: Cleanup connections
    }
    
    /// Store event in feed
    pub fn store(self: *Self, event: FeedEvent) !void {
        _ = self;
        _ = event;
        // TODO: Insert into DuckDB + LanceDB
    }
    
    /// Query feed with filters
    pub fn query(self: *Self, opts: FeedQuery) ![]FeedEvent {
        _ = self;
        _ = opts;
        // TODO: SQL query on DuckDB
        return &[_]FeedEvent{};
    }
    
    /// Semantic search using vector similarity
    pub fn searchSimilar(self: *Self, embedding: [384]f32, limit: usize) ![]FeedEvent {
        _ = self;
        _ = embedding;
        _ = limit;
        // TODO: ANN search in LanceDB
        return &[_]FeedEvent{};
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "FeedEvent encoding" {
    const allocator = std.testing.allocator;
    
    var event = FeedEvent{
        .id = 1706963200000000000,
        .event_type = .post,
        .author = [_]u8{0} ** 32,
        .timestamp = 1706963200000000000,
        .content_hash = [_]u8{0} ** 32,
        .parent_id = null,
        .embedding = null,
        .tags = &.{"libertaria", "zig"},
        .mentions = &.{},
    };
    
    const encoded = try event.encode(allocator);
    defer allocator.free(encoded);
    
    try std.testing.expect(encoded.len > 0);
}

test "FeedQuery defaults" {
    const query = FeedQuery{};
    try std.testing.expectEqual(query.limit, 50);
    try std.testing.expectEqual(query.offset, 0);
}
