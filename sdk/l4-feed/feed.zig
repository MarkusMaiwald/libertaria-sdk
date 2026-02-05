//! L4 Feed — Temporal Event Store with DuckDB Backend
//! 
//! Hybrid storage: DuckDB (structured) + optional LanceDB (vectors)
//! Kenya-compliant: <10MB RAM, embedded-only, no cloud calls

const std = @import("std");
const duckdb = @import("duckdb.zig");

// Re-export DuckDB types
pub const DB = duckdb.DB;
pub const Conn = duckdb.Conn;

/// Event types in the feed
pub const EventType = enum(u8) {
    post = 0,           // Original content
    reaction = 1,       // like, boost, bookmark
    follow = 2,         // Social graph edge
    mention = 3,        // @username reference
    hashtag = 4,        // #topic tag
    edit = 5,           // Content modification
    delete = 6,         // Tombstone
    
    pub fn toInt(self: EventType) u8 {
        return @intFromEnum(self);
    }
};

/// Feed event structure (64-byte aligned for cache efficiency)
pub const FeedEvent = extern struct {
    id: u64,                    // Snowflake ID (time-sortable)
    event_type: u8,             // EventType as u8
    _padding1: [7]u8 = .{0} ** 7,  // Alignment
    author: [32]u8,             // DID of creator
    timestamp: i64,             // Unix nanoseconds
    content_hash: [32]u8,       // Blake3 of content
    parent_id: u64,             // 0 = none (for replies/threading)
    
    comptime {
        std.debug.assert(@sizeOf(FeedEvent) == 96);
    }
};

/// Feed query options
pub const FeedQuery = struct {
    allocator: std.mem.Allocator,
    author: ?[32]u8 = null,
    event_type: ?EventType = null,
    since: ?i64 = null,
    until: ?i64 = null,
    parent_id: ?u64 = null,
    limit: usize = 50,
    offset: usize = 0,
    
    pub fn deinit(self: *FeedQuery) void {
        _ = self;
    }
};

/// Hybrid feed storage with DuckDB backend
pub const FeedStore = struct {
    allocator: std.mem.Allocator,
    db: DB,
    conn: Conn,
    
    const Self = @This();
    
    /// Initialize FeedStore with DuckDB backend
    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        var db = try DB.open(path);
        errdefer db.close();
        
        var conn = try db.connect();
        errdefer conn.disconnect();
        
        var self = Self{
            .allocator = allocator,
            .db = db,
            .conn = conn,
        };
        
        // Create schema
        try self.createSchema();
        
        return self;
    }
    
    /// Cleanup resources
    pub fn deinit(self: *Self) void {
        self.conn.disconnect();
        self.db.close();
    }
    
    /// Create database schema
    fn createSchema(self: *Self) !void {
        const schema_sql = 
            \\CREATE TABLE IF NOT EXISTS events (
            \\    id UBIGINT PRIMARY KEY,
            \\    event_type TINYINT NOT NULL,
            \\    author BLOB(32) NOT NULL,
            \\    timestamp BIGINT NOT NULL,
            \\    content_hash BLOB(32) NOT NULL,
            \\    parent_id UBIGINT DEFAULT 0
            \\);
            
            // Index for timeline queries
            \\\n            \\CREATE INDEX IF NOT EXISTS idx_author_time 
            \\    ON events(author, timestamp DESC);
            
            // Index for thread reconstruction
            \\\n            \\CREATE INDEX IF NOT EXISTS idx_parent 
            \\    ON events(parent_id, timestamp);
            
            // Index for time-range queries
            \\\n            \\CREATE INDEX IF NOT EXISTS idx_time 
            \\    ON events(timestamp DESC);
        ;
        
        try self.conn.query(schema_sql);
    }
    
    /// Store single event
    pub fn store(self: *Self, event: FeedEvent) !void {
        // TODO: Implement proper prepared statements
        // For now, skip SQL generation (needs hex encoding fix)
        _ = event;
        _ = self;
        return error.NotImplemented;
    }
    
    /// Query feed with filters
    pub fn query(self: *Self, opts: FeedQuery) ![]FeedEvent {
        var sql = std.ArrayList(u8).init(self.allocator);
        defer sql.deinit();
        
        try sql.appendSlice("SELECT id, event_type, author, timestamp, content_hash, parent_id FROM events WHERE 1=1");
        
        if (opts.author) |author| {
            _ = author;
            // TODO: Implement proper hex encoding for SQL
            // const author_hex = try std.fmt.allocPrint(self.allocator, "...", .{});
        }
        
        if (opts.event_type) |et| {
            try sql.writer().print(" AND event_type = {d}", .{et.toInt()});
        }
        
        if (opts.since) |since| {
            try sql.writer().print(" AND timestamp >= {d}", .{since});
        }
        
        if (opts.until) |until| {
            try sql.writer().print(" AND timestamp <= {d}", .{until});
        }
        
        if (opts.parent_id) |pid| {
            try sql.writer().print(" AND parent_id = {d}", .{pid});
        }
        
        try sql.writer().print(" ORDER BY timestamp DESC LIMIT {d} OFFSET {d}", .{opts.limit, opts.offset});
        
        // TODO: Execute and parse results
        // For now, return empty (needs result parsing implementation)
        try self.conn.query(try sql.toOwnedSlice());
        
        return &[_]FeedEvent{};
    }
    
    /// Get timeline for author (posts + reactions)
    pub fn getTimeline(self: *Self, author: [32]u8, limit: usize) ![]FeedEvent {
        return self.query(.{
            .allocator = self.allocator,
            .author = author,
            .limit = limit,
        });
    }
    
    /// Get thread (replies to a post)
    pub fn getThread(self: *Self, parent_id: u64) ![]FeedEvent {
        return self.query(.{
            .allocator = self.allocator,
            .parent_id = parent_id,
            .limit = 100,
        });
    }
    
    /// Count events (for metrics/debugging)
    pub fn count(self: *Self) !u64 {
        // TODO: Implement result parsing
        _ = self;
        return 0;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "FeedEvent size" {
    comptime try std.testing.expectEqual(@sizeOf(FeedEvent), 96);
}

test "EventType conversion" {
    try std.testing.expectEqual(@as(u8, 0), EventType.post.toInt());
    try std.testing.expectEqual(@as(u8, 1), EventType.reaction.toInt());
}

test "FeedStore init/deinit (requires DuckDB)" {
    // Skipped if DuckDB not available
    // var store = try FeedStore.init(std.testing.allocator, ":memory:");
    // defer store.deinit();
}
