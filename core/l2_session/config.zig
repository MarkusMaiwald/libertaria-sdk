//! Session configuration

const std = @import("std");

/// Session configuration
pub const SessionConfig = struct {
    /// Time-to-live before requiring re-handshake
    ttl: Duration = .{ .hrs = 24 },

    /// Heartbeat interval
    heartbeat_interval: Duration = .{ .secs = 30 },

    /// Missed heartbeats before degradation
    heartbeat_tolerance: u8 = 3,

    /// Handshake timeout
    handshake_timeout: Duration = .{ .secs = 5 },

    /// Key rotation window (before TTL expires)
    rotation_window: Duration = .{ .hrs = 1 },
};

/// Duration helper
pub const Duration = struct {
    secs: u64 = 0,
    mins: u64 = 0,
    hrs: u64 = 0,

    pub fn seconds(self: Duration) i64 {
        return @intCast(self.secs + self.mins * 60 + self.hrs * 3600);
    }
};
