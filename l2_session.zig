//! Sovereign Index: L2 Session Manager
//! 
//! The L2 Session Manager provides cryptographically verified,
//! resilient peer-to-peer session management for the Libertaria Stack.
//!
//! ## Core Concepts
//!
//! - **Session**: A sovereign state machine representing trust relationship
//! - **Handshake**: PQxdh-based mutual authentication
//! - **Heartbeat**: Cooperative liveness verification
//! - **Rotation**: Seamless key material refresh
//!
//! ## Transport
//!
//! This module uses QUIC and μTCP (micro-transport).
//! WebSockets are explicitly excluded by design (ADR-001).
//!
//! ## Usage
//!
//! ```janus
//! // Establish a session
//! let session = try l2_session.establish(
//!     peer_did: peer_identity,
//!     ctx: ctx
//! );
//!
//! // Send message through session
//! try session.send(message, ctx);
//!
//! // Receive with automatic decryption
//! let response = try session.receive(timeout: 5s, ctx);
//! ```
//!
//! ## Architecture
//!
//! - State machine: Explicit, auditable transitions
//! - Crypto: X25519Kyber768 hybrid (PQ-safe)
//! - Resilience: Graceful degradation, automatic recovery

const std = @import("std");

// Public API exports
pub const Session = @import("l2_session/session.zig").Session;
pub const State = @import("l2_session/state.zig").State;
pub const Handshake = @import("l2_session/handshake.zig").Handshake;
pub const Heartbeat = @import("l2_session/heartbeat.zig").Heartbeat;
pub const KeyRotation = @import("l2_session/rotation.zig").KeyRotation;
pub const Transport = @import("l2_session/transport.zig").Transport;

// Re-export core types
pub const SessionConfig = @import("l2_session/config.zig").SessionConfig;
pub const SessionError = @import("l2_session/error.zig").SessionError;

/// Establish a new session with a peer
/// 
/// This initiates the PQxdh handshake and returns a session in
/// the `handshake_initiated` state. The session becomes `established`
/// after the peer responds.
pub fn establish(
    peer_did: []const u8,
    config: SessionConfig,
    ctx: anytype,
) !Session {
    return Handshake.initiate(peer_did, config, ctx);
}

/// Resume a previously established session
/// 
/// If valid key material exists from a previous session,
/// this reuses it for fast re-establishment.
pub fn resume(
    peer_did: []const u8,
    stored_session: StoredSession,
    ctx: anytype,
) !Session {
    return Handshake.resume(peer_did, stored_session, ctx);
}

/// Accept an incoming session request
/// 
/// Call this when receiving a handshake request from a peer.
pub fn accept(
    request: HandshakeRequest,
    config: SessionConfig,
    ctx: anytype,
) !Session {
    return Handshake.respond(request, config, ctx);
}

/// Process all pending session events
/// 
/// Call this periodically (e.g., in your event loop) to handle
/// heartbeats, timeouts, and state transitions.
pub fn tick(
    sessions: []Session,
    ctx: anytype,
) void {
    for (sessions) |*session| {
        session.tick(ctx);
    }
}
