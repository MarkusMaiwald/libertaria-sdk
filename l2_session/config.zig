//! Session configuration

const std = @import("std");

/// Session configuration
pub const SessionConfig = struct {
    /// Time-to-live before requiring re-handshake
    ttl: Duration = .{ .hours = 24 },
    
    /// Heartbeat interval
    heartbeat_interval: Duration = .{ .seconds = 30 },
    
    /// Missed heartbeats before degradation
    heartbeat_tolerance: u8 = 3,
    
    /// Handshake timeout
    handshake_timeout: Duration = .{ .seconds = 5 },
    
    /// Key rotation window (before TTL expires)
    rotation_window: Duration = .{ .hours = 1 },
};

/// Duration helper
pub const Duration = struct {
    seconds: u64 = 0,
    minutes: u64 = 0,
    hours: u64 = 0,
    
    pub fn seconds(self: Duration) i64 {
        return @intCast(self.seconds + self.minutes * 60 + self.hours * 3600);
    }
};
