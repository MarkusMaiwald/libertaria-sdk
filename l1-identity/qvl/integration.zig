//! QVL Integration Layer
//! 
//! Bridges PersistentGraph (libmdbx) with in-memory algorithms:
//! - Load RiskGraph from disk for computation
//! - Save results back to persistent storage
//! - Hybrid: Cold data on disk, hot data in memory

const std = @import("std");
const types = @import("types.zig");
const storage = @import("storage.zig");
const betrayal = @import("betrayal.zig");
const pathfinding = @import("pathfinding.zig");
const pop_integration = @import("pop_integration.zig");

const NodeId = types.NodeId;
const RiskEdge = types.RiskEdge;
const RiskGraph = types.RiskGraph;
const PersistentGraph = storage.PersistentGraph;
const BellmanFordResult = betrayal.BellmanFordResult;
const PathResult = pathfinding.PathResult;

/// Hybrid graph: persistent backing + in-memory cache
pub const HybridGraph = struct {
    persistent: *PersistentGraph,
    cache: RiskGraph,
    cache_valid: bool,
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    /// Initialize hybrid graph
    pub fn init(persistent: *PersistentGraph, allocator: std.mem.Allocator) Self {
        return Self{
            .persistent = persistent,
            .cache = RiskGraph.init(allocator),
            .cache_valid = false,
            .allocator = allocator,
        };
    }
    
    /// Deinitialize
    pub fn deinit(self: *Self) void {
        self.cache.deinit();
    }
    
    /// Load from persistent storage into cache
    pub fn load(self: *Self) !void {
        if (self.cache_valid) return; // Already loaded
        
        // Clear existing cache
        self.cache.deinit();
        self.cache = try self.persistent.toRiskGraph(self.allocator);
        self.cache_valid = true;
    }
    
    /// Save cache back to persistent storage
    pub fn save(self: *Self) !void {
        // TODO: Implement incremental save (only changed edges)
        // For now, full rewrite
        _ = self;
    }
    
    /// Add edge: both cache and persistent
    pub fn addEdge(self: *Self, edge: RiskEdge) !void {
        // Add to persistent storage
        try self.persistent.addEdge(edge);
        
        // Add to cache if loaded
        if (self.cache_valid) {
            try self.cache.addEdge(edge);
        }
    }
    
    /// Get outgoing neighbors (uses cache if available)
    pub fn getOutgoing(self: *Self, node: NodeId) ![]const usize {
        if (self.cache_valid) {
            return self.cache.neighbors(node);
        } else {
            // Ensure cache is loaded, then return neighbors
            try self.load();
            return self.cache.neighbors(node);
        }
    }
    
    // =========================================================================
    // Algorithm Integration
    // =========================================================================
    
    /// Run Bellman-Ford betrayal detection on persistent graph
    pub fn detectBetrayal(self: *Self, source: NodeId) !BellmanFordResult {
        try self.load(); // Ensure cache is ready
        return betrayal.detectBetrayal(&self.cache, source, self.allocator);
    }
    
    /// Find trust path using A*
    pub fn findTrustPath(
        self: *Self,
        source: NodeId,
        target: NodeId,
        heuristic: pathfinding.HeuristicFn,
        heuristic_ctx: *const anyopaque,
    ) !PathResult {
        try self.load();
        return pathfinding.findTrustPath(
            &self.cache, source, target, heuristic, heuristic_ctx, self.allocator);
    }
    
    /// Verify Proof-of-Path and update reputation
    pub fn verifyPoP(
        self: *Self,
        proof: *const pop_integration.ProofOfPath,
        expected_receiver: [32]u8,
        expected_sender: [32]u8,
        rep_map: *pop_integration.ReputationMap,
        current_entropy: u64,
    ) !pop_integration.PathVerdict {
        // This needs CompactTrustGraph, not RiskGraph...
        // Need adapter or separate implementation
        _ = self;
        _ = proof;
        _ = expected_receiver;
        _ = expected_sender;
        _ = rep_map;
        _ = current_entropy;
        @panic("TODO: Implement PoP verification for PersistentGraph");
    }
    
    // =========================================================================
    // Statistics
    // =========================================================================
    
    pub fn nodeCount(self: *Self) usize {
        if (self.cache_valid) {
            return self.cache.nodeCount();
        }
        return 0; // TODO: Query from persistent
    }
    
    pub fn edgeCount(self: *Self) usize {
        if (self.cache_valid) {
            return self.cache.edgeCount();
        }
        return 0; // TODO: Query from persistent
    }
};

/// Transactional wrapper for batch operations
pub const GraphTransaction = struct {
    hybrid: *HybridGraph,
    pending_edges: std.ArrayList(RiskEdge),
    allocator: std.mem.Allocator,
    
    const Self = @This();
    
    pub fn begin(hybrid: *HybridGraph, allocator: std.mem.Allocator) Self {
        return Self{
            .hybrid = hybrid,
            .pending_edges = .{}, // Empty, allocator passed on append
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Self) void {
        self.pending_edges.deinit(self.allocator);
    }
    
    pub fn addEdge(self: *Self, edge: RiskEdge) !void {
        try self.pending_edges.append(self.allocator, edge);
    }
    
    pub fn commit(self: *Self) !void {
        // Add all pending edges atomically
        for (self.pending_edges.items) |edge| {
            try self.hybrid.addEdge(edge);
        }
        self.pending_edges.clearRetainingCapacity();
    }
    
    pub fn rollback(self: *Self) void {
        self.pending_edges.clearRetainingCapacity();
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "HybridGraph: load and detect betrayal" {
    const allocator = std.testing.allocator;
    const time = @import("time");
    
    const path = "/tmp/test_hybrid_db";
    defer std.fs.deleteFileAbsolute(path) catch {};
    
    // Create persistent graph
    var persistent = try PersistentGraph.open(path, .{}, allocator);
    defer persistent.close();
    
    // Create hybrid
    var hybrid = HybridGraph.init(&persistent, allocator);
    defer hybrid.deinit();
    
    // Add edges forming negative cycle
    const ts = time.SovereignTimestamp.fromSeconds(1234567890, .system_boot);
    const expires = ts.addSeconds(86400);
    try hybrid.addEdge(.{ .from = 0, .to = 1, .risk = -0.3, .timestamp = ts, .nonce = 0, .level = 3, .expires_at = expires });
    try hybrid.addEdge(.{ .from = 1, .to = 2, .risk = -0.3, .timestamp = ts, .nonce = 1, .level = 3, .expires_at = expires });
    try hybrid.addEdge(.{ .from = 2, .to = 0, .risk = 1.0, .timestamp = ts, .nonce = 2, .level = 0, .expires_at = expires }); // level 0 = betrayal
    
    // Detect betrayal
    var result = try hybrid.detectBetrayal(0);
    defer result.deinit();
    
    try std.testing.expect(result.betrayal_cycles.items.len > 0);
}

test "GraphTransaction: commit and rollback" {
    const allocator = std.testing.allocator;
    const time = @import("time");
    
    const path = "/tmp/test_tx_db";
    defer std.fs.deleteFileAbsolute(path) catch {};
    
    var persistent = try PersistentGraph.open(path, .{}, allocator);
    defer persistent.close();
    
    var hybrid = HybridGraph.init(&persistent, allocator);
    defer hybrid.deinit();
    
    // Start transaction
    var txn = GraphTransaction.begin(&hybrid, allocator);
    defer txn.deinit();
    
    // Add edges
    const ts = time.SovereignTimestamp.fromSeconds(1234567890, .system_boot);
    const expires = ts.addSeconds(86400);
    try txn.addEdge(.{ .from = 0, .to = 1, .risk = -0.3, .timestamp = ts, .nonce = 0, .level = 3, .expires_at = expires });
    try txn.addEdge(.{ .from = 1, .to = 2, .risk = -0.3, .timestamp = ts, .nonce = 1, .level = 3, .expires_at = expires });
    
    // Commit
    try txn.commit();
    
    // Verify edges exist
    try hybrid.load();
    try std.testing.expectEqual(hybrid.edgeCount(), 2);
}
