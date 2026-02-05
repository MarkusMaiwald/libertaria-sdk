// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Libertaria Contributors
// This file is part of the Libertaria Core, licensed under
// The Libertaria Commonwealth License v1.0.


//! RFC-0010 & RFC-0020: L0 Integrated Service
//!
//! Orchestrates the flow: [Network] -> [UTCP] -> [OPQ] -> [Application]

const std = @import("std");
const utcp = @import("utcp");
const opq = @import("opq");
const lwf = @import("lwf");

pub const L0Service = struct {
    allocator: std.mem.Allocator,
    socket: utcp.UTCP,
    opq_manager: opq.OPQManager,

    /// Initialize the L0 service with a bound socket and storage
    pub fn init(allocator: std.mem.Allocator, address: std.net.Address, base_dir: []const u8, persona: opq.Persona, resolver: opq.trust_resolver.TrustResolver) !L0Service {
        return L0Service{
            .allocator = allocator,
            .socket = try utcp.UTCP.init(allocator, address),
            .opq_manager = try opq.OPQManager.init(allocator, base_dir, persona, resolver),
        };
    }

    pub fn deinit(self: *L0Service) void {
        self.socket.deinit();
        self.opq_manager.deinit();
    }

    /// Process a single frame from the network
    /// Returns true if a frame was successfully ingested
    pub fn step(self: *L0Service) !bool {
        var buffer: [9000]u8 = undefined; // Jumbo MTU support

        const result = self.socket.receiveFrame(self.allocator, &buffer) catch |err| {
            if (err == error.WouldBlock) return false;
            return err;
        };

        var frame = result.frame;
        defer frame.deinit(self.allocator);

        // 1. Verification (Deep)
        if (!frame.verifyChecksum()) return error.ChecksumMismatch;

        // 2. Persistence (The Queue)
        try self.opq_manager.ingestFrame(&frame);

        return true;
    }
};

test "L0 Integrated Service: Loopback Ingestion" {
    const allocator = std.testing.allocator;
    const test_dir = "test_l0_service";

    std.fs.cwd().deleteTree(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    const addr = try std.net.Address.parseIp("127.0.0.1", 0);

    // 1. Start Service (Relay persona)
    var service = try L0Service.init(allocator, addr, test_dir, .relay, opq.trust_resolver.TrustResolver.noop());
    defer service.deinit();

    const service_addr = try service.socket.getLocalAddress();

    // 2. Prepare client socket and frame
    var client = try utcp.UTCP.init(std.testing.allocator, try std.net.Address.parseIp("127.0.0.1", 0));
    defer client.deinit();

    var frame = try lwf.LWFFrame.init(allocator, 100);
    defer frame.deinit(allocator);
    @memset(frame.payload, 'X');
    frame.header.payload_len = 100;
    frame.updateChecksum();

    // 3. Send and Step
    try client.sendFrame(service_addr, &frame, allocator);

    const success = try service.step();
    try std.testing.expect(success);

    // 4. Verify storage contains the frame (via DiskUsage)
    const usage = try service.opq_manager.store.getDiskUsage();
    try std.testing.expect(usage > 0);
}
