//! View Logic for Capsule TUI
//! Renders the "Luxury Deck" interface.

const std = @import("std");
const vaxis = @import("vaxis");
const app_mod = @import("app.zig");

pub fn draw(app: *app_mod.AppState, win: vaxis.Window) !void {
    // 1. Draw Header
    const header = win.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = win.width,
        .height = 3,
    });
    header.fill(vaxis.Cell{ .style = .{ .bg = .{ .rgb = .{ 20, 20, 30 } } } });

    _ = header.printSegment(.{ .text = " CAPSULE OS ", .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bold = true } }, .{ .row_offset = 1, .col_offset = 2 });

    // Tabs
    const tabs = [_][]const u8{ "Dashboard", "Slash Log", "Trust Graph" };
    var col: usize = 20;
    for (tabs, 0..) |tab, i| {
        const is_active = i == @intFromEnum(app.active_tab);
        const style: vaxis.Style = if (is_active)
            .{ .fg = .{ .rgb = .{ 255, 255, 255 } }, .bg = .{ .rgb = .{ 60, 60, 80 } }, .bold = true }
        else
            .{ .fg = .{ .rgb = .{ 150, 150, 150 } } };

        _ = header.printSegment(.{ .text = tab, .style = style }, .{ .row_offset = 1, .col_offset = @intCast(col) });
        col += tab.len + 4;
    }

    // 2. Draw Content Area
    const content = win.child(.{
        .x_off = 0,
        .y_off = 3,
        .width = win.width,
        .height = win.height - 3,
    });

    switch (app.active_tab) {
        .Dashboard => try drawDashboard(app, content),
        .SlashLog => try drawSlashLog(app, content),
        .TrustGraph => try drawTrustGraph(app, content),
    }
}

fn drawDashboard(app: *app_mod.AppState, win: vaxis.Window) !void {
    if (app.node_status) |status| {
        // Node ID
        var buf: [128]u8 = undefined;
        const id_str = try std.fmt.bufPrint(&buf, "Node ID: {s}", .{status.node_id});
        _ = win.printSegment(.{ .text = id_str, .style = .{ .fg = .{ .rgb = .{ 100, 200, 100 } } } }, .{ .row_offset = 1, .col_offset = 2 });

        // State
        const state_str = try std.fmt.bufPrint(&buf, "State:   {s}", .{status.state});
        _ = win.printSegment(.{ .text = state_str }, .{ .row_offset = 2, .col_offset = 2 });

        // Version
        const ver_str = try std.fmt.bufPrint(&buf, "Version: {s}", .{status.version});
        _ = win.printSegment(.{ .text = ver_str }, .{ .row_offset = 3, .col_offset = 2 });

        // Peers
        const peers_str = try std.fmt.bufPrint(&buf, "Peers:   {}", .{status.peers_count});
        _ = win.printSegment(.{ .text = peers_str }, .{ .row_offset = 4, .col_offset = 2 });
    } else {
        _ = win.printSegment(.{ .text = "Fetching status...", .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } } }, .{ .row_offset = 2, .col_offset = 2 });
    }
}

fn drawSlashLog(app: *app_mod.AppState, win: vaxis.Window) !void {
    // Header
    _ = win.printSegment(.{ .text = "Target DID", .style = .{ .bold = true, .ul_style = .single } }, .{ .row_offset = 1, .col_offset = 2 });
    _ = win.printSegment(.{ .text = "Reason", .style = .{ .bold = true, .ul_style = .single } }, .{ .row_offset = 1, .col_offset = 40 });
    _ = win.printSegment(.{ .text = "Severity", .style = .{ .bold = true, .ul_style = .single } }, .{ .row_offset = 1, .col_offset = 70 });

    var row: u16 = 2;
    for (app.slash_log.items) |ev| {
        if (row >= win.height) break;

        _ = win.printSegment(.{ .text = ev.target_did }, .{ .row_offset = row, .col_offset = 2 });
        _ = win.printSegment(.{ .text = ev.reason }, .{ .row_offset = row, .col_offset = 40 });
        _ = win.printSegment(.{ .text = ev.severity }, .{ .row_offset = row, .col_offset = 70 });

        row += 1;
    }

    if (app.slash_log.items.len == 0) {
        _ = win.printSegment(.{ .text = "No slash events recorded.", .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } } }, .{ .row_offset = 3, .col_offset = 2 });
    }
}

fn drawTrustGraph(app: *app_mod.AppState, win: vaxis.Window) !void {
    // 1. Draw Title
    _ = win.printSegment(.{ .text = "QVL TRUST LATTICE", .style = .{ .bold = true, .fg = .{ .rgb = .{ 100, 255, 255 } } } }, .{ .row_offset = 1, .col_offset = 2 });

    if (app.topology) |topo| {
        // Center of the radar
        const cx: usize = win.width / 2;
        const cy: usize = win.height / 2;

        // Max radius (smaller of width/height / 2, minus margin)
        const max_radius = @min(cx, cy) - 2;

        // Draw Rings (Orbits)
        // 25%, 50%, 75%, 100% Trust
        // Cannot draw circles easily with characters, so we just imply them by node position
        // Or we could draw axes. Let's draw axes.

        // X-Axis
        // for (2..win.width-2) |x| {
        //     _ = win.printSegment(.{ .text = "-", .style = .{ .fg = .{ .rgb = .{ 60, 60, 60 } } } }, .{ .row_offset = @intCast(cy), .col_offset = @intCast(x) });
        // }
        // Y-Axis
        // for (2..win.height-1) |y| {
        //     _ = win.printSegment(.{ .text = "|", .style = .{ .fg = .{ .rgb = .{ 60, 60, 60 } } } }, .{ .row_offset = @intCast(y), .col_offset = @intCast(cx) });
        // }

        // Draw Nodes
        const nodes_count = topo.nodes.len;
        // Skip self (index 0) loop for now to draw it specially at center

        // Self
        _ = win.printSegment(.{ .text = "★", .style = .{ .bold = true, .fg = .{ .rgb = .{ 255, 215, 0 } } } }, .{ .row_offset = @intCast(cy), .col_offset = @intCast(cx) });
        _ = win.printSegment(.{ .text = "SELF" }, .{ .row_offset = @intCast(cy + 1), .col_offset = @intCast(cx - 2) });

        // Peers
        // We will distribute them by angle (index) and radius (1.0 - trust)
        // Trust 1.0 = Center (0 radius)
        // Trust 0.0 = Edge (max radius)

        const count_f: f64 = @floatFromInt(nodes_count);

        for (topo.nodes, 0..) |node, i| {
            if (i == 0) continue; // Skip self

            const angle = (2.0 * std.math.pi * @as(f64, @floatFromInt(i))) / count_f;
            const dist_factor = 1.0 - node.trust_score; // Higher trust = closer to center
            const radius = dist_factor * @as(f64, @floatFromInt(max_radius));

            // Polar to Cartesian
            const dx = @cos(angle) * (radius * 2.0); // *2 for aspect ratio correction (roughly)
            const dy = @sin(angle) * radius;

            const px: usize = @intCast(@as(i64, @intCast(cx)) + @as(i64, @intFromFloat(dx)));
            const py: usize = @intCast(@as(i64, @intCast(cy)) + @as(i64, @intFromFloat(dy)));

            // Bound check
            if (px > 0 and px < win.width and py > 0 and py < win.height) {
                // Style based on status
                var style: vaxis.Style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } };
                var char: []const u8 = "o";

                if (std.mem.eql(u8, node.status, "slashed")) {
                    style = .{ .fg = .{ .rgb = .{ 255, 50, 50 } }, .bold = true, .blink = true };
                    char = "X";
                } else if (node.trust_score > 0.8) {
                    style = .{ .fg = .{ .rgb = .{ 100, 255, 100 } }, .bold = true };
                    char = "⬢";
                }

                _ = win.printSegment(.{ .text = char, .style = style }, .{ .row_offset = @intCast(py), .col_offset = @intCast(px) });

                // Label (ID)
                if (win.width > 60) {
                    _ = win.printSegment(.{ .text = node.id, .style = .{ .dim = true } }, .{ .row_offset = @intCast(py + 1), .col_offset = @intCast(px) });
                }
            }
        }
    } else {
        _ = win.printSegment(.{ .text = "Waiting for Topology Data...", .style = .{ .blink = true } }, .{ .row_offset = 2, .col_offset = 4 });
    }
}
