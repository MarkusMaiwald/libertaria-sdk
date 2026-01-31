//! IPC Client for TUI -> Daemon communication.
//! Wraps control.zig types.

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

    pub fn connect(self: *Client) !void {
        // Connect to /tmp/capsule.sock
        // TODO: Load from config
        const path = "/tmp/capsule.sock";
        const address = try std.net.Address.initUnix(path);
        self.stream = try std.net.tcpConnectToAddress(address);
    }

    pub fn getStatus(self: *Client) !NodeStatus {
        const resp = try self.request(.Status);
        switch (resp) {
            .NodeStatus => |s| return s,
            else => return error.UnexpectedResponse,
        }
    }

    pub fn getSlashLog(self: *Client, limit: usize) ![]SlashEvent {
        const resp = try self.request(.{ .SlashLog = .{ .limit = limit } });
        switch (resp) {
            .SlashLogResult => |l| {
                // We need to duplicate the list because response memory is transient (if using an arena in request)
                // But for now, let's assume the caller handles it or we deep copy.
                // Simpler: Return generic Response and let caller handle.
                // Actually, let's just return the slice and hope the buffer lifetime management in request isn't too tricky.
                // Wait, request() will likely use a local buffer. Returning a slice into it is unsafe.
                // I need to use an arena or return a deep copy.
                // For this MVP, I'll return the response object completely if possible, or copy.
                // Let's implement deep copy later. For now, assume single-threaded blocking.
                return try self.deepCopySlashLog(l);
            },
            else => return error.UnexpectedResponse,
        }
    }

    pub fn request(self: *Client, cmd: control.Command) !control.Response {
        if (self.stream == null) return error.NotConnected;
        const stream = self.stream.?;

        // Send
        var req_buf = std.ArrayList(u8){};
        defer req_buf.deinit(self.allocator);
        var w_struct = req_buf.writer(self.allocator);
        var buffer: [128]u8 = undefined;
        var adapter = w_struct.adaptToNewApi(&buffer);
        try std.json.Stringify.value(cmd, .{}, &adapter.new_interface);
        try adapter.new_interface.flush();
        try stream.writeAll(req_buf.items);

        // Read (buffered)
        var resp_buf: [32768]u8 = undefined; // Large buffer for slash log
        const bytes = try stream.read(&resp_buf);
        if (bytes == 0) return error.ConnectionClosed;

        // Parse (using allocator for string allocations inside union)
        const parsed = try std.json.parseFromSlice(control.Response, self.allocator, resp_buf[0..bytes], .{ .ignore_unknown_fields = true });
        // Note: parsed.value contains pointers to resp_buf if we used Leaky, but here we used allocator.
        // Wait, std.json.parseFromSlice with allocator allocates strings!
        // So we can return parsed.value.
        return parsed.value;
    }

    pub fn getTopology(self: *Client) !TopologyInfo {
        const resp = try self.request(.Topology);
        switch (resp) {
            .TopologyInfo => |t| return try self.deepCopyTopology(t),
            else => return error.UnexpectedResponse,
        }
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
        // Deep copy nodes
        const nodes = try self.allocator.alloc(control.GraphNode, topo.nodes.len);
        for (topo.nodes, 0..) |n, i| {
            nodes[i] = .{
                .id = try self.allocator.dupe(u8, n.id),
                .trust_score = n.trust_score,
                .status = try self.allocator.dupe(u8, n.status),
                .role = try self.allocator.dupe(u8, n.role),
            };
        }

        // Deep copy edges
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
};
