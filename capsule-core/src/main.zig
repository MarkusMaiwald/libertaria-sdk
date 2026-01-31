//! Capsule Core Entry Point

const std = @import("std");
const node_mod = @import("node.zig");
const config_mod = @import("config.zig");

const control_mod = @import("control.zig");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "start")) {
        try runDaemon(allocator);
    } else if (std.mem.eql(u8, command, "status")) {
        try runCliCommand(allocator, .Status);
    } else if (std.mem.eql(u8, command, "peers")) {
        try runCliCommand(allocator, .Peers);
    } else if (std.mem.eql(u8, command, "stop")) {
        try runCliCommand(allocator, .Shutdown);
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Libertaria Capsule v0.1.0 (Shield)\n", .{});
    } else if (std.mem.eql(u8, command, "slash")) {
        if (args.len < 5) {
            std.debug.print("Usage: capsule slash <target_did> <reason> <severity>\n", .{});
            return;
        }
        const target_did = args[2];
        const reason = args[3];
        const severity = args[4];

        // Validation could happen here or in node
        try runCliCommand(allocator, .{ .Slash = .{
            .target_did = try allocator.dupe(u8, target_did),
            .reason = try allocator.dupe(u8, reason),
            .severity = try allocator.dupe(u8, severity),
            .duration = 0,
        } });
    } else if (std.mem.eql(u8, command, "slash-log")) {
        var limit: usize = 50;
        if (args.len >= 3) {
            limit = std.fmt.parseInt(usize, args[2], 10) catch 50;
        }
        try runCliCommand(allocator, .{ .SlashLog = .{ .limit = limit } });
    } else if (std.mem.eql(u8, command, "ban")) {
        if (args.len < 4) {
            std.debug.print("Usage: capsule ban <did> <reason>\n", .{});
            return;
        }
        const target_did = args[2];
        const reason = args[3];
        try runCliCommand(allocator, .{ .Ban = .{
            .target_did = try allocator.dupe(u8, target_did),
            .reason = try allocator.dupe(u8, reason),
        } });
    } else if (std.mem.eql(u8, command, "unban")) {
        if (args.len < 3) {
            std.debug.print("Usage: capsule unban <did>\n", .{});
            return;
        }
        const target_did = args[2];
        try runCliCommand(allocator, .{ .Unban = .{
            .target_did = try allocator.dupe(u8, target_did),
        } });
    } else if (std.mem.eql(u8, command, "trust")) {
        if (args.len < 4) {
            std.debug.print("Usage: capsule trust <did> <score>\n", .{});
            return;
        }
        const target_did = args[2];
        const score = std.fmt.parseFloat(f64, args[3]) catch {
            std.debug.print("Error: Invalid score '{s}', must be a number\n", .{args[3]});
            return;
        };
        try runCliCommand(allocator, .{ .Trust = .{
            .target_did = try allocator.dupe(u8, target_did),
            .score = score,
        } });
    } else if (std.mem.eql(u8, command, "sessions")) {
        try runCliCommand(allocator, .Sessions);
    } else if (std.mem.eql(u8, command, "dht")) {
        try runCliCommand(allocator, .Dht);
    } else if (std.mem.eql(u8, command, "qvl-query")) {
        var target_did: ?[]const u8 = null;
        if (args.len >= 3) {
            target_did = try allocator.dupe(u8, args[2]);
        }
        try runCliCommand(allocator, .{ .QvlQuery = .{ .target_did = target_did } });
    } else if (std.mem.eql(u8, command, "identity")) {
        try runCliCommand(allocator, .Identity);
    } else if (std.mem.eql(u8, command, "lockdown")) {
        try runCliCommand(allocator, .Lockdown);
    } else if (std.mem.eql(u8, command, "unlock")) {
        try runCliCommand(allocator, .Unlock);
    } else if (std.mem.eql(u8, command, "airlock")) {
        const state = if (args.len > 2) args[2] else "open";
        try runCliCommand(allocator, .{ .Airlock = .{ .state = state } });
    } else {
        printUsage();
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: capsule <command>
        \\
        \\Commands:
        \\  start    Start the Capsule daemon
        \\  status   Check node status
        \\  peers    List connected peers
        \\  stop     Shutdown the daemon
        \\  version    Print version
        \\  slash      <did> <reason> <severity>  Slash a node
        \\  slash-log  [limit]                    View slash history
        \\  ban        <did> <reason>             Ban a peer
        \\  unban      <did>                      Unban a peer
        \\  trust      <did> <score>              Set trust override
        \\  sessions                              List active sessions
        \\  dht                                   Show DHT status
        \\  qvl-query  [did]                      Query QVL metrics
        \\  identity                              Show node identity
        \\  lockdown                              Emergency network lockdown
        \\  unlock                                Resume normal operation
        \\  airlock    <open|restricted|closed>  Set airlock mode
        \\
    , .{});
}

fn runDaemon(allocator: std.mem.Allocator) !void {
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

    // Run Node
    try node.start();
}

fn runCliCommand(allocator: std.mem.Allocator, cmd: control_mod.Command) !void {
    // Load config to find socket path
    const config_path = "config.json";
    var config = config_mod.NodeConfig.loadFromJsonFile(allocator, config_path) catch {
        std.log.err("Failed to load config to find control socket. Is config.json present?", .{});
        return error.ConfigLoadFailed;
    };
    defer config.deinit(allocator);

    const socket_path = config.control_socket_path;

    var stream = std.net.connectUnixSocket(socket_path) catch |err| {
        std.log.err("Failed to connect to daemon at {s}: {}. Is it running?", .{ socket_path, err });
        return err;
    };
    defer stream.close();

    // Send Command
    var req_buf = std.ArrayList(u8){};
    defer req_buf.deinit(allocator);
    var w_struct = req_buf.writer(allocator);
    var buffer: [128]u8 = undefined;
    var adapter = w_struct.adaptToNewApi(&buffer);
    try std.json.Stringify.value(cmd, .{}, &adapter.new_interface);
    try adapter.new_interface.flush();
    try stream.writeAll(req_buf.items);

    // Read Response
    var resp_buf: [4096]u8 = undefined;
    const bytes = try stream.read(&resp_buf);

    if (bytes == 0) {
        std.log.err("Empty response from daemon", .{});
        return;
    }

    std.debug.print("{s}\n", .{resp_buf[0..bytes]});
}
