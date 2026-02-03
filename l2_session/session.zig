//! Session struct and core API
//!
//! The Session is the primary interface for L2 peer communication.

const std = @import("std");
const State = @import("state.zig").State;
const SessionConfig = @import("config.zig").SessionConfig;
const SessionError = @import("error.zig").SessionError;

/// A sovereign session with a peer
///
/// Sessions are state machines that manage the lifecycle of a
/// cryptographically verified peer relationship.
pub const Session = struct {
    /// Peer DID (decentralized identifier)
    peer_did: []const u8,
    
    /// Current state in the state machine
    state: State,
    
    /// Configuration
    config: SessionConfig,
    
    /// Session keys (post-handshake)
    keys: ?SessionKeys,
    
    /// Creation timestamp
    created_at: i64,
    
    /// Last activity timestamp
    last_activity: i64,
    
    /// TTL deadline
    ttl_deadline: i64,
    
    /// Heartbeat tracking
    missed_heartbeats: u8,
    
    /// Retry tracking
    retry_count: u8,
    
    const Self = @This();
    
    /// Create a new session in idle state
    pub fn new(peer_did: []const u8, config: SessionConfig) Self {
        const now = std.time.timestamp();
        return .{
            .peer_did = peer_did,
            .state = .idle,
            .config = config,
            .keys = null,
            .created_at = now,
            .last_activity = now,
            .ttl_deadline = now + config.ttl.seconds(),
            .missed_heartbeats = 0,
            .retry_count = 0,
        };
    }
    
    /// Process one tick of the state machine
    /// Call this regularly from your event loop
    pub fn tick(self: *Self, ctx: anytype) void {
        // TODO: Implement state machine transitions
        _ = self;
        _ = ctx;
    }
    
    /// Send a message through this session
    pub fn send(self: *Self, message: []const u8, ctx: anytype) !void {
        // TODO: Implement encryption and transmission
        _ = self;
        _ = message;
        _ = ctx;
    }
    
    /// Receive a message from this session
    pub fn receive(self: *Self, timeout_ms: u32, ctx: anytype) ![]const u8 {
        // TODO: Implement reception and decryption
        _ = self;
        _ = timeout_ms;
        _ = ctx;
        return &[]const u8{};
    }
};

/// Session encryption keys (derived from PQxdh)
const SessionKeys = struct {
    /// Encryption key (ChaCha20-Poly1305)
    enc_key: [32]u8,
    
    /// Decryption key
    dec_key: [32]u8,
    
    /// Authentication key for heartbeats
    auth_key: [32]u8,
};

/// Stored session data for persistence
pub const StoredSession = struct {
    peer_did: []const u8,
    keys: SessionKeys,
    created_at: i64,
};
