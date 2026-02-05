//! Transport abstraction (QUIC / μTCP)
//!
//! No WebSockets. See ADR-001.

const std = @import("std");

/// Transport abstraction
pub const Transport = struct {
    /// Send data to peer
    pub fn send(data: []const u8, ctx: anytype) !void {
        // TODO: Implement QUIC primary, μTCP fallback
        _ = data;
        _ = ctx;
    }
    
    /// Receive data from peer
    pub fn receive(timeout_ms: u32, ctx: anytype) !?[]const u8 {
        // TODO: Implement reception
        _ = timeout_ms;
        _ = ctx;
        return null;
    }
};
