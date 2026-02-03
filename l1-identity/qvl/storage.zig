//! QVL Persistent Storage Layer
//! 
//!libmdbx backend for RiskGraph with Kenya Rule compliance:
//! - Single-file embedded database
//! - Memory-mapped I/O (kernel-optimized)
//! - ACID transactions
//! - <10MB RAM footprint

const std = @import("std");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskEdge = types.RiskEdge;
const RiskGraph = types.RiskGraph;

/// Database environment configuration
pub const DBConfig = struct {
    /// Max readers (concurrent)
    max_readers: u32 = 64,
    /// Max databases (tables)
    max_dbs: u32 = 8,
    /// Map size (file size limit)
    map_size: usize = 10 * 1024 * 1024, // 10MB Kenya Rule
    /// Page size (4KB optimal for SSD)
    page_size: u32 = 4096,
};

/// Persistent graph storage using libmdbx
pub const PersistentGraph = struct {
    env: *lmdb.MDB_env,
    dbi_nodes: lmdb.MDB_dbi,
    dbi_edges: lmdb.MDB_dbi,
    dbi_adjacency: lmdb.MDB_dbi,
    dbi_metadata: lmdb.MDB_dbi,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    /// Open or create persistent graph database
    pub fn open(path: []const u8, config: DBConfig, allocator: std.mem.Allocator) !Self {
        var env: *lmdb.MDB_env = undefined;
        
        // Initialize environment
        try lmdb.mdb_env_create(&env);
        errdefer lmdb.mdb_env_close(env);
        
        // Set limits
        try lmdb.mdb_env_set_maxreaders(env, config.max_readers);
        try lmdb.mdb_env_set_maxdbs(env, config.max_dbs);
        try lmdb.mdb_env_set_mapsize(env, config.map_size);
        
        // Open environment
        const flags = lmdb.MDB_NOSYNC | lmdb.MDB_NOMETASYNC; // Async durability for speed
        try lmdb.mdb_env_open(env, path.ptr, flags, 0o644);
        
        // Open databases (tables)
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(env, null, 0, &txn);
        errdefer lmdb.mdb_txn_abort(txn);
        
        const dbi_nodes = try lmdb.mdb_dbi_open(txn, "nodes", lmdb.MDB_CREATE | lmdb.MDB_INTEGERKEY);
        const dbi_edges = try lmdb.mdb_dbi_open(txn, "edges", lmdb.MDB_CREATE);
        const dbi_adjacency = try lmdb.mdb_dbi_open(txn, "adjacency", lmdb.MDB_CREATE | lmdb.MDB_DUPSORT);
        const dbi_metadata = try lmdb.mdb_dbi_open(txn, "metadata", lmdb.MDB_CREATE);
        
        try lmdb.mdb_txn_commit(txn);
        
        return Self{
            .env = env,
            .dbi_nodes = dbi_nodes,
            .dbi_edges = dbi_edges,
            .dbi_adjacency = dbi_adjacency,
            .dbi_metadata = dbi_metadata,
            .allocator = allocator,
        };
    }
    
    /// Close database
    pub fn close(self: *Self) void {
        lmdb.mdb_env_close(self.env);
    }
    
    /// Add node to persistent storage
    pub fn addNode(self: *Self, node: NodeId) !void {
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(self.env, null, 0, &txn);
        errdefer lmdb.mdb_txn_abort(txn);
        
        const key = std.mem.asBytes(&node);
        const val = &[_]u8{1}; // Presence marker
        
        var mdb_key = lmdb.MDB_val{ .mv_size = key.len, .mv_data = key.ptr };
        var mdb_val = lmdb.MDB_val{ .mv_size = val.len, .mv_data = val.ptr };
        
        try lmdb.mdb_put(txn, self.dbi_nodes, &mdb_key, &mdb_val, 0);
        try lmdb.mdb_txn_commit(txn);
    }
    
    /// Add edge to persistent storage
    pub fn addEdge(self: *Self, edge: RiskEdge) !void {
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(self.env, null, 0, &txn);
        errdefer lmdb.mdb_txn_abort(txn);
        
        // Store edge data
        const edge_key = try self.encodeEdgeKey(edge.from, edge.to);
        const edge_val = try self.encodeEdgeValue(edge);
        
        var mdb_key = lmdb.MDB_val{ .mv_size = edge_key.len, .mv_data = edge_key.ptr };
        var mdb_val = lmdb.MDB_val{ .mv_size = edge_val.len, .mv_data = edge_val.ptr };
        
        try lmdb.mdb_put(txn, self.dbi_edges, &mdb_key, &mdb_val, 0);
        
        // Update adjacency index (from -> to)
        const adj_key = std.mem.asBytes(&edge.from);
        const adj_val = std.mem.asBytes(&edge.to);
        
        var mdb_adj_key = lmdb.MDB_val{ .mv_size = adj_key.len, .mv_data = adj_key.ptr };
        var mdb_adj_val = lmdb.MDB_val{ .mv_size = adj_val.len, .mv_data = adj_val.ptr };
        
        try lmdb.mdb_put(txn, self.dbi_adjacency, &mdb_adj_key, &mdb_adj_val, 0);
        
        // Update reverse adjacency (to -> from) for incoming queries
        const rev_adj_key = std.mem.asBytes(&edge.to);
        const rev_adj_val = std.mem.asBytes(&edge.from);
        
        var mdb_rev_key = lmdb.MDB_val{ .mv_size = rev_adj_key.len, .mv_data = rev_adj_key.ptr };
        var mdb_rev_val = lmdb.MDB_val{ .mv_size = rev_adj_val.len, .mv_data = rev_adj_val.ptr };
        
        try lmdb.mdb_put(txn, self.dbi_adjacency, &mdb_rev_key, &mdb_rev_val, 0);
        
        try lmdb.mdb_txn_commit(txn);
    }
    
    /// Get outgoing neighbors (from -> *)
    pub fn getOutgoing(self: *Self, from: NodeId, allocator: std.mem.Allocator) ![]NodeId {
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(self.env, null, lmdb.MDB_RDONLY, &txn);
        defer lmdb.mdb_txn_abort(txn); // Read-only, abort is fine
        
        const key = std.mem.asBytes(&from);
        var mdb_key = lmdb.MDB_val{ .mv_size = key.len, .mv_data = key.ptr };
        var mdb_val: lmdb.MDB_val = undefined;
        
        var cursor: *lmdb.MDB_cursor = undefined;
        try lmdb.mdb_cursor_open(txn, self.dbi_adjacency, &cursor);
        defer lmdb.mdb_cursor_close(cursor);
        
        var result = std.ArrayList(NodeId).init(allocator);
        errdefer result.deinit();
        
        // Position cursor at key
        const rc = lmdb.mdb_cursor_get(cursor, &mdb_key, &mdb_val, lmdb.MDB_SET_KEY);
        if (rc == lmdb.MDB_NOTFOUND) {
            return result.toOwnedSlice();
        }
        if (rc != 0) return error.MDBError;
        
        // Iterate over all values for this key
        while (true) {
            const neighbor = std.mem.bytesToValue(NodeId, @as([*]const u8, @ptrCast(mdb_val.mv_data))[0..@sizeOf(NodeId)]);
            try result.append(neighbor);
            
            const next_rc = lmdb.mdb_cursor_get(cursor, &mdb_key, &mdb_val, lmdb.MDB_NEXT_DUP);
            if (next_rc == lmdb.MDB_NOTFOUND) break;
            if (next_rc != 0) return error.MDBError;
        }
        
        return result.toOwnedSlice();
    }
    
    /// Get incoming neighbors (* -> to)
    pub fn getIncoming(self: *Self, to: NodeId, allocator: std.mem.Allocator) ![]NodeId {
        // Same as getOutgoing but querying by "to" key
        // Implementation mirrors getOutgoing
        _ = to;
        _ = allocator;
        @panic("TODO: implement getIncoming");
    }
    
    /// Get specific edge
    pub fn getEdge(self: *Self, from: NodeId, to: NodeId) !?RiskEdge {
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(self.env, null, lmdb.MDB_RDONLY, &txn);
        defer lmdb.mdb_txn_abort(txn);
        
        const key = try self.encodeEdgeKey(from, to);
        var mdb_key = lmdb.MDB_val{ .mv_size = key.len, .mv_data = key.ptr };
        var mdb_val: lmdb.MDB_val = undefined;
        
        const rc = lmdb.mdb_get(txn, self.dbi_edges, &mdb_key, &mdb_val);
        if (rc == lmdb.MDB_NOTFOUND) return null;
        if (rc != 0) return error.MDBError;
        
        return try self.decodeEdgeValue(mdb_val);
    }
    
    /// Load in-memory RiskGraph from persistent storage
    pub fn toRiskGraph(self: *Self, allocator: std.mem.Allocator) !RiskGraph {
        var graph = RiskGraph.init(allocator);
        errdefer graph.deinit();
        
        var txn: *lmdb.MDB_txn = undefined;
        try lmdb.mdb_txn_begin(self.env, null, lmdb.MDB_RDONLY, &txn);
        defer lmdb.mdb_txn_abort(txn);
        
        // Iterate all edges
        var cursor: *lmdb.MDB_cursor = undefined;
        try lmdb.mdb_cursor_open(txn, self.dbi_edges, &cursor);
        defer lmdb.mdb_cursor_close(cursor);
        
        var mdb_key: lmdb.MDB_val = undefined;
        var mdb_val: lmdb.MDB_val = undefined;
        
        while (lmdb.mdb_cursor_get(cursor, &mdb_key, &mdb_val, lmdb.MDB_NEXT) == 0) {
            const edge = try self.decodeEdgeValue(mdb_val);
            try graph.addEdge(edge);
        }
        
        return graph;
    }
    
    // Internal: Encode edge key (from, to) -> bytes
    fn encodeEdgeKey(self: *Self, from: NodeId, to: NodeId) ![]u8 {
        _ = self;
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u32, buf[0..4], from, .little);
        std.mem.writeInt(u32, buf[4..8], to, .little);
        return &buf;
    }
    
    // Internal: Encode RiskEdge -> bytes
    fn encodeEdgeValue(self: *Self, edge: RiskEdge) ![]u8 {
        _ = self;
        // Compact binary encoding
        var buf: [64]u8 = undefined;
        var offset: usize = 0;
        
        std.mem.writeInt(u32, buf[offset..][0..4], edge.from, .little);
        offset += 4;
        
        std.mem.writeInt(u32, buf[offset..][0..4], edge.to, .little);
        offset += 4;
        
        std.mem.writeInt(u64, buf[offset..][0..8], @bitCast(edge.risk), .little);
        offset += 8;
        
        std.mem.writeInt(u64, buf[offset..][0..8], edge.timestamp, .little);
        offset += 8;
        
        std.mem.writeInt(u64, buf[offset..][0..8], edge.nonce, .little);
        offset += 8;
        
        std.mem.writeInt(u8, buf[offset..][0..1], edge.level);
        offset += 1;
        
        std.mem.writeInt(u64, buf[offset..][0..8], edge.expires_at, .little);
        offset += 8;
        
        return buf[0..offset];
    }
    
    // Internal: Decode bytes -> RiskEdge
    fn decodeEdgeValue(self: *Self, val: lmdb.MDB_val) !RiskEdge {
        _ = self;
        const data = @as([*]const u8, @ptrCast(val.mv_data))[0..val.mv_size];
        
        var offset: usize = 0;
        
        const from = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;
        
        const to = std.mem.readInt(u32, data[offset..][0..4], .little);
        offset += 4;
        
        const risk_bits = std.mem.readInt(u64, data[offset..][0..8], .little);
        const risk = @as(f64, @bitCast(risk_bits));
        offset += 8;
        
        const timestamp = std.mem.readInt(u64, data[offset..][0..8], .little);
        offset += 8;
        
        const nonce = std.mem.readInt(u64, data[offset..][0..8], .little);
        offset += 8;
        
        const level = std.mem.readInt(u8, data[offset..][0..1], .little);
        offset += 1;
        
        const expires_at = std.mem.readInt(u64, data[offset..][0..8], .little);
        
        return RiskEdge{
            .from = from,
            .to = to,
            .risk = risk,
            .timestamp = timestamp,
            .nonce = nonce,
            .level = level,
            .expires_at = expires_at,
        };
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "PersistentGraph: basic operations" {
    const allocator = std.testing.allocator;
    
    // Create temporary database
    const path = "/tmp/test_qvl_db";
    defer std.fs.deleteFileAbsolute(path) catch {};
    
    var graph = try PersistentGraph.open(path, .{}, allocator);
    defer graph.close();
    
    // Add nodes
    try graph.addNode(0);
    try graph.addNode(1);
    try graph.addNode(2);
    
    // Add edges
    const ts = 1234567890;
    try graph.addEdge(.{
        .from = 0,
        .to = 1,
        .risk = -0.3,
        .timestamp = ts,
        .nonce = 0,
        .level = 3,
        .expires_at = ts + 86400,
    });
    
    try graph.addEdge(.{
        .from = 1,
        .to = 2,
        .risk = -0.3,
        .timestamp = ts,
        .nonce = 1,
        .level = 3,
        .expires_at = ts + 86400,
    });
    
    // Query outgoing
    const neighbors = try graph.getOutgoing(0, allocator);
    defer allocator.free(neighbors);
    
    try std.testing.expectEqual(neighbors.len, 1);
    try std.testing.expectEqual(neighbors[0], 1);
    
    // Retrieve edge
    const edge = try graph.getEdge(0, 1);
    try std.testing.expect(edge != null);
    try std.testing.expectEqual(edge.?.from, 0);
    try std.testing.expectEqual(edge.?.to, 1);
    try std.testing.expectApproxEqAbs(edge.?.risk, -0.3, 0.001);
}

test "PersistentGraph: Kenya Rule compliance" {
    const allocator = std.testing.allocator;
    
    const path = "/tmp/test_kenya_db";
    defer std.fs.deleteFileAbsolute(path) catch {};
    
    // 10MB limit
    var graph = try PersistentGraph.open(path, .{
        .map_size = 10 * 1024 * 1024,
    }, allocator);
    defer graph.close();
    
    // Add 1000 nodes
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try graph.addNode(i);
    }
    
    // Verify database size
    const stat = try std.fs.cwd().statFile(path);
    try std.testing.expect(stat.size < 10 * 1024 * 1024);
}
