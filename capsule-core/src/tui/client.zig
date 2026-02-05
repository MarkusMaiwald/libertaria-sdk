//! IPC Client for TUI -> Daemon communication.
//! Wraps control.zig types with deep-copying logic for memory safety.

const std = @import("std");
const control = @import("../control.zig");

pub const NodeStatus = control.NodeStatus;
pub const SlashEvent = control.SlashEvent;
pub const TopologyInfo = control.TopologyInfo;
pub const GraphNode = control.GraphNode;
pub const GraphEdge = control.GraphEdge;

pub const Client = struct {
    allocator: std.mem.Allocator,
    stream: ?std.net.Stream = null,

    pub fn init(allocator: std.mem.Allocator) !Client {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Client) void {
        if (self.stream) |s| s.close();
    }

    pub fn connect(self: *Client, socket_path: []const u8) !void {
        self.stream = std.net.connectUnixSocket(socket_path) catch |err| {
            std.log.err("Failed to connect to daemon at {s}: {}. Is it running?", .{ socket_path, err });
            return err;
        };
    }

    pub fn getStatus(self: *Client) !NodeStatus {
        var parsed = try self.request(.Status);
        defer parsed.deinit();

        switch (parsed.value) {
            .NodeStatus => |s| return try self.deepCopyStatus(s),
            else => return error.UnexpectedResponse,
        }
    }

    pub fn getSlashLog(self: *Client, limit: usize) ![]SlashEvent {
        var parsed = try self.request(.{ .SlashLog = .{ .limit = limit } });
        defer parsed.deinit();

        switch (parsed.value) {
            .SlashLogResult => |l| return try self.deepCopySlashLog(l),
            else => return error.UnexpectedResponse,
        }
    }

    pub fn getTopology(self: *Client) !TopologyInfo {
        var parsed = try self.request(.Topology);
        defer parsed.deinit();

        switch (parsed.value) {
            .TopologyInfo => |t| return try self.deepCopyTopology(t),
            else => return error.UnexpectedResponse,
        }
    }

    pub fn request(self: *Client, cmd: control.Command) !std.json.Parsed(control.Response) {
        if (self.stream == null) return error.NotConnected;
        const stream = self.stream.?;

        const json_bytes = try std.json.Stringify.valueAlloc(self.allocator, cmd, .{});
        defer self.allocator.free(json_bytes);
        try stream.writeAll(json_bytes);

        var resp_buf: [32768]u8 = undefined;
        const bytes = try stream.read(&resp_buf);
        if (bytes == 0) return error.ConnectionClosed;

        return try std.json.parseFromSlice(control.Response, self.allocator, resp_buf[0..bytes], .{ .ignore_unknown_fields = true });
    }

    fn deepCopyStatus(self: *Client, s: NodeStatus) !NodeStatus {
        return .{
            .node_id = try self.allocator.dupe(u8, s.node_id),
            .state = try self.allocator.dupe(u8, s.state),
            .peers_count = s.peers_count,
            .uptime_seconds = s.uptime_seconds,
            .version = try self.allocator.dupe(u8, s.version),
        };
    }

    fn deepCopySlashLog(self: *Client, events: []const SlashEvent) ![]SlashEvent {
        const list = try self.allocator.alloc(SlashEvent, events.len);
        for (events, 0..) |ev, i| {
            list[i] = .{
                .timestamp = ev.timestamp,
                .target_did = try self.allocator.dupe(u8, ev.target_did),
                .reason = try self.allocator.dupe(u8, ev.reason),
                .severity = try self.allocator.dupe(u8, ev.severity),
                .evidence_hash = try self.allocator.dupe(u8, ev.evidence_hash),
            };
        }
        return list;
    }

    fn deepCopyTopology(self: *Client, topo: TopologyInfo) !TopologyInfo {
        const nodes = try self.allocator.alloc(control.GraphNode, topo.nodes.len);
        for (topo.nodes, 0..) |n, i| {
            nodes[i] = .{
                .id = try self.allocator.dupe(u8, n.id),
                .trust_score = n.trust_score,
                .status = try self.allocator.dupe(u8, n.status),
                .role = try self.allocator.dupe(u8, n.role),
            };
        }

        const edges = try self.allocator.alloc(control.GraphEdge, topo.edges.len);
        for (topo.edges, 0..) |e, i| {
            edges[i] = .{
                .source = try self.allocator.dupe(u8, e.source),
                .target = try self.allocator.dupe(u8, e.target),
                .weight = e.weight,
            };
        }

        return TopologyInfo{
            .nodes = nodes,
            .edges = edges,
        };
    }

    pub fn freeStatus(self: *Client, s: NodeStatus) void {
        self.allocator.free(s.node_id);
        self.allocator.free(s.state);
        self.allocator.free(s.version);
    }

    pub fn freeSlashLog(self: *Client, events: []SlashEvent) void {
        for (events) |ev| {
            self.allocator.free(ev.target_did);
            self.allocator.free(ev.reason);
            self.allocator.free(ev.severity);
            self.allocator.free(ev.evidence_hash);
        }
        self.allocator.free(events);
    }

    pub fn freeTopology(self: *Client, topo: TopologyInfo) void {
        for (topo.nodes) |n| {
            self.allocator.free(n.id);
            self.allocator.free(n.status);
            self.allocator.free(n.role);
        }
        self.allocator.free(topo.nodes);

        for (topo.edges) |e| {
            self.allocator.free(e.source);
            self.allocator.free(e.target);
        }
        self.allocator.free(topo.edges);
    }
};
