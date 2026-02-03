//! QVL Storage Layer - Stub Implementation
//! 
//! This is a stub/mock implementation for testing without libmdbx.
//! Replace with real libmdbx implementation when available.

const std = @import("std");
const types = @import("types.zig");

const NodeId = types.NodeId;
const RiskEdge = types.RiskEdge;
const RiskGraph = types.RiskGraph;

/// Mock persistent storage using in-memory HashMap
pub const PersistentGraph = struct {
    allocator: std.mem.Allocator,
    nodes: std.AutoHashMap(NodeId, void),
    edges: std.AutoHashMap(EdgeKey, RiskEdge),
    adjacency: std.AutoHashMap(NodeId, std.ArrayList(NodeId)),
    path: []const u8,
    
    const EdgeKey = struct {
        from: NodeId,
        to: NodeId,
        
        pub fn hash(self: EdgeKey) u64 {
            return @as(u64, self.from) << 32 | self.to;
        }
        
        pub fn eql(self: EdgeKey, other: EdgeKey) bool {
            return self.from == other.from and self.to == other.to;
        }
    };
    
    const Self = @This();
    
    /// Open or create persistent graph (mock: in-memory)
    pub fn open(path: []const u8, config: DBConfig, allocator: std.mem.Allocator) !Self {
        _ = config;
        return Self{
            .allocator = allocator,
            .nodes = std.AutoHashMap(NodeId, void).init(allocator),
            .edges = std.AutoHashMap(EdgeKey, RiskEdge).init(allocator),
            .adjacency = std.AutoHashMap(NodeId, std.ArrayList(NodeId)).init(allocator),
            .path = try allocator.dupe(u8, path),
        };
    }
    
    /// Close database
    pub fn close(self: *Self) void {
        // Clean up adjacency lists
        var it = self.adjacency.valueIterator();
        while (it.next()) |list| {
            list.deinit(self.allocator);
        }
        self.adjacency.deinit();
        self.edges.deinit();
        self.nodes.deinit();
        self.allocator.free(self.path);
    }
    
    /// Add node
    pub fn addNode(self: *Self, node: NodeId) !void {
        try self.nodes.put(node, {});
    }
    
    /// Add edge
    pub fn addEdge(self: *Self, edge: RiskEdge) !void {
        // Register nodes first
        try self.nodes.put(edge.from, {});
        try self.nodes.put(edge.to, {});
        
        const key = EdgeKey{ .from = edge.from, .to = edge.to };
        try self.edges.put(key, edge);
        
        // Update adjacency
        const entry = try self.adjacency.getOrPut(edge.from);
        if (!entry.found_existing) {
            entry.value_ptr.* = .{}; // Empty ArrayList, allocator passed on append
        }
        try entry.value_ptr.append(self.allocator, edge.to);
    }
    
    /// Get outgoing neighbors
    pub fn getOutgoing(self: *Self, node: NodeId, allocator: std.mem.Allocator) ![]NodeId {
        if (self.adjacency.get(node)) |list| {
            // Copy to new slice with provided allocator
            return allocator.dupe(NodeId, list.items);
        }
        return allocator.dupe(NodeId, &[_]NodeId{});
    }
    
    /// Get specific edge
    pub fn getEdge(self: *Self, from: NodeId, to: NodeId) !?RiskEdge {
        const key = EdgeKey{ .from = from, .to = to };
        return self.edges.get(key);
    }
    
    /// Load in-memory RiskGraph
    pub fn toRiskGraph(self: *Self, allocator: std.mem.Allocator) !RiskGraph {
        var graph = RiskGraph.init(allocator);
        errdefer graph.deinit();
        
        // First add all nodes
        var node_it = self.nodes.keyIterator();
        while (node_it.next()) |node| {
            try graph.addNode(node.*);
        }
        
        // Then add all edges
        var edge_it = self.edges.valueIterator();
        while (edge_it.next()) |edge| {
            try graph.addEdge(edge.*);
        }
        
        return graph;
    }
};

/// Database configuration (mock accepts same config for API compatibility)
pub const DBConfig = struct {
    max_readers: u32 = 64,
    max_dbs: u32 = 8,
    map_size: usize = 10 * 1024 * 1024,
    page_size: u32 = 4096,
};

// Re-export for integration.zig
pub const lmdb = struct {
    // Stub exports
};
