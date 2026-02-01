//! Capsule TUI Application
//! Built with Vaxis (The "Luxury Deck").

const std = @import("std");
const vaxis = @import("vaxis");

const control = @import("control");
const client_mod = @import("client.zig");
const view_mod = @import("view.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    update_data: void,
};

pub const AppState = struct {
    allocator: std.mem.Allocator,
    should_quit: bool,
    client: client_mod.Client,

    // UI State
    active_tab: enum { Dashboard, SlashLog, TrustGraph } = .Dashboard,

    // Data State (Protected by mutex)
    mutex: std.Thread.Mutex = .{},
    node_status: ?client_mod.NodeStatus = null,
    slash_log: std.ArrayList(client_mod.SlashEvent),
    topology: ?client_mod.TopologyInfo = null,

    pub fn init(allocator: std.mem.Allocator) !AppState {
        return .{
            .allocator = allocator,
            .should_quit = false,
            .client = try client_mod.Client.init(allocator),
            .slash_log = std.ArrayList(client_mod.SlashEvent){},
            .topology = null,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *AppState) void {
        if (self.node_status) |s| self.client.freeStatus(s);

        for (self.slash_log.items) |ev| {
            self.client.allocator.free(ev.target_did);
            self.client.allocator.free(ev.reason);
            self.client.allocator.free(ev.severity);
            self.client.allocator.free(ev.evidence_hash);
        }
        self.slash_log.deinit(self.allocator);

        if (self.topology) |t| self.client.freeTopology(t);

        self.client.deinit();
    }
};

pub fn run(allocator: std.mem.Allocator, socket_path: []const u8) !void {
    var app = try AppState.init(allocator);
    defer app.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(allocator, .{});
    // Initialize TTY
    var tty = try vaxis.Tty.init(&.{});
    defer tty.deinit();

    defer vx.deinit(allocator, tty.writer());

    // Event Loop
    var loop: vaxis.Loop(Event) = .{ .vaxis = &vx, .tty = &tty };
    try loop.init();
    try loop.start();
    defer loop.stop();

    // Connect to Daemon
    try app.client.connect(socket_path);

    // Spawn Data Thread
    const DataThread = struct {
        fn run(l: *vaxis.Loop(Event), a: *AppState) void {
            while (!a.should_quit) {
                // Poll Status
                if (a.client.getStatus()) |status| {
                    a.mutex.lock();
                    defer a.mutex.unlock();
                    if (a.node_status) |old| a.client.freeStatus(old);
                    a.node_status = status;
                } else |_| {}

                // Poll Slash Log
                if (a.client.getSlashLog(20)) |logs| {
                    a.mutex.lock();
                    defer a.mutex.unlock();
                    // Free strings in existing events before clearing
                    for (a.slash_log.items) |ev| {
                        a.client.allocator.free(ev.target_did);
                        a.client.allocator.free(ev.reason);
                        a.client.allocator.free(ev.severity);
                        a.client.allocator.free(ev.evidence_hash);
                    }
                    a.slash_log.clearRetainingCapacity();
                    a.slash_log.appendSlice(a.allocator, logs) catch {};
                    a.allocator.free(logs);
                } else |_| {}

                // Poll Topology
                if (a.client.getTopology()) |topo| {
                    a.mutex.lock();
                    defer a.mutex.unlock();
                    if (a.topology) |old| a.client.freeTopology(old);
                    a.topology = topo;
                } else |_| {}

                // Notify UI to redraw
                l.postEvent(.{ .update_data = {} });

                std.Thread.sleep(1 * std.time.ns_per_s);
            }
        }
    };

    var thread = try std.Thread.spawn(.{}, DataThread.run, .{ &loop, &app });
    defer thread.join();

    while (!app.should_quit) {
        // Handle Events
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    app.should_quit = true;
                }
                // Handle tab switching
                if (key.matches(vaxis.Key.tab, .{})) {
                    app.active_tab = switch (app.active_tab) {
                        .Dashboard => .SlashLog,
                        .SlashLog => .TrustGraph,
                        .TrustGraph => .Dashboard,
                    };
                }
            },
            .winsize => |ws| {
                try vx.resize(allocator, tty.writer(), ws);
            },
            .update_data => {}, // Handled by redraw below
        }

        // Global Redraw
        {
            app.mutex.lock();
            defer app.mutex.unlock();
            const win = vx.window();
            win.clear();
            try view_mod.draw(&app, win);
            try vx.render(tty.writer());
        }
    }
}
