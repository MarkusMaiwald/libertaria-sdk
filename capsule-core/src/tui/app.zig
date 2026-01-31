//! Capsule TUI Application (Stub)
//! Vaxis dependency temporarily removed to fix build.

const std = @import("std");

pub const App = struct {
    pub fn run(_: *anyopaque) !void {
        std.log.info("TUI functionality temporarily disabled.", .{});
    }
};

pub fn run(allocator: std.mem.Allocator, control_socket_path: []const u8) !void {
    _ = allocator;
    _ = control_socket_path;
    std.log.info("TUI functionality temporarily disabled.", .{});
}
