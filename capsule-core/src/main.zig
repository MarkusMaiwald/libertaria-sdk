//! Capsule Core Entry Point

const std = @import("std");
const node_mod = @import("node.zig");
const config_mod = @import("config.zig");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup logging (default to info)
    // std.log is configured via root declarations in build.zig usually, or std options.

    // Parse args (Minimal for Week 27)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1 and std.mem.eql(u8, args[1], "version")) {
        std.debug.print("Libertaria Capsule v0.1.0 (Shield)\n", .{});
        return;
    }

    // Load Config
    // Check for config.json, otherwise use default
    const config_path = "config.json";
    var config = config_mod.NodeConfig.loadFromJsonFile(allocator, config_path) catch |err| {
        std.log.err("Failed to load configuration: {}", .{err});
        return err;
    };
    defer config.deinit(allocator);

    // Initialize Node
    const node = try node_mod.CapsuleNode.init(allocator, config);
    defer node.deinit();

    // Setup signal handler for clean shutdown (Ctrl+C)
    // (Zig std doesn't have cross-platform signal handling yet, assume simplified loop for now)

    // Run Node
    try node.start();
}
