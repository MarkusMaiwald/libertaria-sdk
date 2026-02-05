//! Key rotation without service interruption
//!
//! Seamlessly rotates session keys before TTL expiration.

const std = @import("std");
const Session = @import("session.zig").Session;

/// Key rotation manager
pub const KeyRotation = struct {
    /// Check if rotation is needed
    pub fn isNeeded(session: *Session, now: i64) bool {
        const time_to_expiry = session.ttl_deadline - now;
        return time_to_expiry <= session.config.rotation_window.seconds();
    }
    
    /// Initiate key rotation
    pub fn initiate(session: *Session, ctx: anytype) !void {
        // TODO: Generate new ephemeral keys
        // TODO: Initiate re-handshake
        _ = session;
        _ = ctx;
    }
    
    /// Complete rotation with new keys
    pub fn complete(session: *Session, new_keys: SessionKeys) void {
        // TODO: Atomically swap keys
        // TODO: Update TTL
        _ = session;
        _ = new_keys;
    }
};

const SessionKeys = @import("session.zig").SessionKeys;
