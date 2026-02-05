//! State machine definitions for L2 sessions
//!
//! States represent the lifecycle of a peer relationship.

const std = @import("std");

/// Session states
///
/// See SPEC.md for full state diagram and transition rules.
pub const State = enum {
    /// Initial state
    idle,
    
    /// Handshake initiated, awaiting response
    handshake_initiated,
    
    /// Handshake received, preparing response
    handshake_received,
    
    /// Active, healthy session
    established,
    
    /// Connectivity issues detected
    degraded,
    
    /// Key rotation in progress
    rotating,
    
    /// Extended failure, pending cleanup or retry
    suspended,
    
    /// Terminal failure state
    failed,
    
    /// Check if this state allows sending messages
    pub fn canSend(self: State) bool {
        return switch (self) {
            .established, .degraded, .rotating => true,
            else => false,
        };
    }
    
    /// Check if this state allows receiving messages
    pub fn canReceive(self: State) bool {
        return switch (self) {
            .established, .degraded, .rotating, .handshake_received => true,
            else => false,
        };
    }
    
    /// Check if this is a terminal state
    pub fn isTerminal(self: State) bool {
        return switch (self) {
            .suspended, .failed => true,
            else => false,
        };
    }
};

/// State transition events
pub const Event = enum {
    initiate_handshake,
    receive_handshake,
    receive_response,
    send_response,
    receive_ack,
    heartbeat_ok,
    heartbeat_missed,
    timeout,
    connectivity_restored,
    time_to_rotate,
    rotation_complete,
    rotation_timeout,
    invalid_signature,
    cleanup,
    retry,
};

/// Attempt state transition
/// Returns new state or null if transition is invalid
pub fn transition(current: State, event: Event) ?State {
    return switch (current) {
        .idle => switch (event) {
            .initiate_handshake => .handshake_initiated,
            .receive_handshake => .handshake_received,
            else => null,
        },
        
        .handshake_initiated => switch (event) {
            .receive_response => .established,
            .timeout => .failed,
            .invalid_signature => .failed,
            else => null,
        },
        
        .handshake_received => switch (event) {
            .send_response => .established,
            .timeout => .failed,
            else => null,
        },
        
        .established => switch (event) {
            .heartbeat_missed => .degraded,
            .time_to_rotate => .rotating,
            else => null,
        },
        
        .degraded => switch (event) {
            .connectivity_restored => .established,
            .timeout => .suspended,
            else => null,
        },
        
        .rotating => switch (event) {
            .rotation_complete => .established,
            .rotation_timeout => .failed,
            else => null,
        },
        
        .suspended => switch (event) {
            .cleanup => null, // Terminal
            .retry => .handshake_initiated,
            else => null,
        },
        
        .failed => switch (event) {
            .cleanup => null, // Terminal
            .retry => .handshake_initiated,
            else => null,
        },
    };
}
