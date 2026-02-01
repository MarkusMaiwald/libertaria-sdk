//! Capsule Core Entry Point

const std = @import("std");
const node_mod = @import("node.zig");
const config_mod = @import("config.zig");

const control_mod = @import("control");
const tui_app = @import("tui/app.zig");

pub fn main() !void {
    // Setup allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var data_dir_override: ?[]const u8 = null;
    var port_override: ?u16 = null;

    // Parse global options and find command index
    var cmd_idx: usize = 1;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--data-dir") and i + 1 < args.len) {
            data_dir_override = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            port_override = std.fmt.parseInt(u16, args[i + 1], 10) catch null;
            i += 1;
        } else {
            cmd_idx = i;
            break;
        }
    }

    if (cmd_idx >= args.len) {
        printUsage();
        return;
    }

    const command = args[cmd_idx];

    if (std.mem.eql(u8, command, "start")) {
        // start already parses its own but we can unify
        try runDaemon(allocator, port_override, data_dir_override);
    } else if (std.mem.eql(u8, command, "status")) {
        try runCliCommand(allocator, .Status, data_dir_override);
    } else if (std.mem.eql(u8, command, "peers")) {
        try runCliCommand(allocator, .Peers, data_dir_override);
    } else if (std.mem.eql(u8, command, "stop")) {
        try runCliCommand(allocator, .Shutdown, data_dir_override);
    } else if (std.mem.eql(u8, command, "version")) {
        std.debug.print("Libertaria Capsule v0.1.0 (Shield)\n", .{});
    } else if (std.mem.eql(u8, command, "slash")) {
        if (args.len < cmd_idx + 4) {
            std.debug.print("Usage: capsule slash <target_did> <reason> <severity>\n", .{});
            return;
        }
        const target_did = args[cmd_idx + 1];
        const reason = args[cmd_idx + 2];
        const severity = args[cmd_idx + 3];

        try runCliCommand(allocator, .{ .Slash = .{
            .target_did = try allocator.dupe(u8, target_did),
            .reason = try allocator.dupe(u8, reason),
            .severity = try allocator.dupe(u8, severity),
            .duration = 0,
        } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "slash-log")) {
        var limit: usize = 50;
        if (args.len >= cmd_idx + 2) {
            limit = std.fmt.parseInt(usize, args[cmd_idx + 1], 10) catch 50;
        }
        try runCliCommand(allocator, .{ .SlashLog = .{ .limit = limit } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "ban")) {
        if (args.len < cmd_idx + 3) {
            std.debug.print("Usage: capsule ban <did> <reason>\n", .{});
            return;
        }
        const target_did = args[cmd_idx + 1];
        const reason = args[cmd_idx + 2];
        try runCliCommand(allocator, .{ .Ban = .{
            .target_did = try allocator.dupe(u8, target_did),
            .reason = try allocator.dupe(u8, reason),
        } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "unban")) {
        if (args.len < cmd_idx + 2) {
            std.debug.print("Usage: capsule unban <did>\n", .{});
            return;
        }
        const target_did = args[cmd_idx + 1];
        try runCliCommand(allocator, .{ .Unban = .{
            .target_did = try allocator.dupe(u8, target_did),
        } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "trust")) {
        if (args.len < cmd_idx + 3) {
            std.debug.print("Usage: capsule trust <did> <score>\n", .{});
            return;
        }
        const target_did = args[cmd_idx + 1];
        const score = std.fmt.parseFloat(f64, args[cmd_idx + 2]) catch {
            std.debug.print("Error: Invalid score '{s}', must be a number\n", .{args[cmd_idx + 2]});
            return;
        };
        try runCliCommand(allocator, .{ .Trust = .{
            .target_did = try allocator.dupe(u8, target_did),
            .score = score,
        } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "sessions")) {
        try runCliCommand(allocator, .Sessions, data_dir_override);
    } else if (std.mem.eql(u8, command, "dht")) {
        try runCliCommand(allocator, .Dht, data_dir_override);
    } else if (std.mem.eql(u8, command, "qvl-query")) {
        var target_did: ?[]const u8 = null;
        if (args.len >= cmd_idx + 2) {
            target_did = try allocator.dupe(u8, args[cmd_idx + 1]);
        }
        try runCliCommand(allocator, .{ .QvlQuery = .{ .target_did = target_did } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "identity")) {
        try runCliCommand(allocator, .Identity, data_dir_override);
    } else if (std.mem.eql(u8, command, "lockdown")) {
        try runCliCommand(allocator, .Lockdown, data_dir_override);
    } else if (std.mem.eql(u8, command, "unlock")) {
        try runCliCommand(allocator, .Unlock, data_dir_override);
    } else if (std.mem.eql(u8, command, "airlock")) {
        const state = if (args.len > cmd_idx + 1) args[cmd_idx + 1] else "open";
        try runCliCommand(allocator, .{ .Airlock = .{ .state = state } }, data_dir_override);
    } else if (std.mem.eql(u8, command, "monitor")) {
        // Load config to find socket path
        const config_path = "config.json";
        var config = config_mod.NodeConfig.loadFromJsonFile(allocator, config_path) catch {
            std.log.err("Failed to load config for monitor. Is config.json present?", .{});
            return error.ConfigLoadFailed;
        };
        defer config.deinit(allocator);

        const data_dir = data_dir_override orelse config.data_dir;
        const socket_path = if (std.fs.path.isAbsolute(config.control_socket_path))
            try allocator.dupe(u8, config.control_socket_path)
        else
            try std.fs.path.join(allocator, &[_][]const u8{ data_dir, std.fs.path.basename(config.control_socket_path) });
        defer allocator.free(socket_path);

        try tui_app.run(allocator, socket_path);
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
        \\  airlock    <open|restricted|closed>   Set airlock mode
        \\  monitor                               Launch TUI Dashboard
        \\
    , .{});
}

fn runDaemon(allocator: std.mem.Allocator, port_override: ?u16, data_dir_override: ?[]const u8) !void {
    // Load Config
    // Check for config.json, otherwise use default
    const config_path = "config.json";
    var config = config_mod.NodeConfig.loadFromJsonFile(allocator, config_path) catch |err| {
        if (err == error.FileNotFound) {
            std.log.info("Config missing, using defaults", .{});
            var cfg = try config_mod.NodeConfig.default(allocator);
            if (port_override) |p| cfg.port = p;
            if (data_dir_override) |d| {
                allocator.free(cfg.data_dir);
                cfg.data_dir = try allocator.dupe(u8, d);
            }
            const node = try node_mod.CapsuleNode.init(allocator, cfg);
            defer node.deinit();
            try node.start();
            return;
        }
        std.log.err("Failed to load configuration: {}", .{err});
        return err;
    };
    defer config.deinit(allocator);

    // Apply Overrides
    if (port_override) |p| config.port = p;
    if (data_dir_override) |d| {
        allocator.free(config.data_dir);
        config.data_dir = try allocator.dupe(u8, d);
    }

    // Initialize Node
    const node = try node_mod.CapsuleNode.init(allocator, config);
    defer node.deinit();

    // Run Node
    try node.start();
}

fn runCliCommand(allocator: std.mem.Allocator, cmd: control_mod.Command, data_dir_override: ?[]const u8) !void {
    // Load config to find socket path
    const config_path = "config.json";
    var config = config_mod.NodeConfig.loadFromJsonFile(allocator, config_path) catch {
        std.log.err("Failed to load config to find control socket. Is config.json present?", .{});
        return error.ConfigLoadFailed;
    };
    defer config.deinit(allocator);

    const data_dir = data_dir_override orelse config.data_dir;
    const socket_path = if (std.fs.path.isAbsolute(config.control_socket_path))
        try allocator.dupe(u8, config.control_socket_path)
    else
        try std.fs.path.join(allocator, &[_][]const u8{ data_dir, std.fs.path.basename(config.control_socket_path) });
    defer allocator.free(socket_path);

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
