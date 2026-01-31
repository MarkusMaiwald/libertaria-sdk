//! Configuration for the Libertaria Capsule Node.

const std = @import("std");

pub const NodeConfig = struct {
    /// Data directory for persistent state (DB, keys, etc.)
    data_dir: []const u8,

    /// UTCP bind port (default: 8710)
    port: u16 = 8710,

    /// Bootstrap peers (multiaddrs)
    bootstrap_peers: [][]const u8 = &.{},

    /// Logging level
    log_level: std.log.Level = .info,

    /// Free allocated memory (strings, slices)
    pub fn deinit(self: *NodeConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.data_dir);
        for (self.bootstrap_peers) |peer| {
            allocator.free(peer);
        }
        allocator.free(self.bootstrap_peers);
    }

    pub fn default(allocator: std.mem.Allocator) !NodeConfig {
        // Default data dir: ~/.libertaria (or "data" for MVP)
        return NodeConfig{
            .data_dir = try allocator.dupe(u8, "data"),
            .port = 8710,
        };
    }

    /// Load configuration from a JSON file
    pub fn loadFromJsonFile(allocator: std.mem.Allocator, path: []const u8) !NodeConfig {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                // If config missing, create default
                std.log.info("Config file not found at {s}, creating default...", .{path});
                const cfg = try NodeConfig.default(allocator);
                try cfg.saveToJsonFile(path);
                return cfg;
            }
            return err;
        };
        defer file.close();

        const max_size = 1024 * 1024; // 1MB config limit
        const content = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(content);

        // Parse JSON
        const parsed = try std.json.parseFromSlice(NodeConfig, allocator, content, .{
            .allocate = .alloc_always,
        });
        defer parsed.deinit();

        // Deep copy strings because parsed.value shares memory with arena/content in some modes,
        // but here we used alloc_always so fields are allocated.
        // However, std.json.parseFromSlice returns a Parsed(T) which manages the memory.
        // We need to detach or copy the data to return a standalone NodeConfig.
        // For simplicity and safety: manually duplicate into new struct.

        const cfg = parsed.value;
        const data_dir = try allocator.dupe(u8, cfg.data_dir);

        var peers = std.array_list.Managed([]const u8).init(allocator);
        for (cfg.bootstrap_peers) |peer| {
            try peers.append(try allocator.dupe(u8, peer));
        }

        return NodeConfig{
            .data_dir = data_dir,
            .port = cfg.port,
            .bootstrap_peers = try peers.toOwnedSlice(),
            .log_level = cfg.log_level,
        };
    }

    /// Save configuration to a JSON file
    pub fn saveToJsonFile(self: *const NodeConfig, path: []const u8) !void {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        var buf = std.array_list.Managed(u8).init(std.heap.page_allocator);
        defer buf.deinit();
        try buf.writer().print("{f}", .{std.json.fmt(self, .{ .whitespace = .indent_4 })});
        try file.writeAll(buf.items);
    }
};
