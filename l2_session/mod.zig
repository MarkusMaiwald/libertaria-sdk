//! Sovereign Index: L2 Session Manager
//! 
//! The L2 Session Manager provides cryptographically verified,
//! resilient peer-to-peer session management for the Libertaria Stack.

const std = @import("std");

// Public API exports
pub const Session = @import("session.zig").Session;
pub const State = @import("state.zig").State;
pub const Handshake = @import("handshake.zig").Handshake;
pub const Heartbeat = @import("heartbeat.zig").Heartbeat;
pub const KeyRotation = @import("rotation.zig").KeyRotation;

// Re-export core types
pub const SessionConfig = @import("config.zig").SessionConfig;
pub const SessionError = @import("error.zig").SessionError;

test {
    std.testing.refAllDecls(@This());
}
