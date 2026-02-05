//! Session error types

const std = @import("std");

/// Session-specific errors
pub const SessionError = error{
    /// Operation timed out
    Timeout,
    
    /// Peer authentication failed
    AuthenticationFailed,
    
    /// Transport layer failure
    TransportFailed,
    
    /// Key rotation failed
    KeyRotationFailed,
    
    /// Invalid state for operation
    InvalidState,
    
    /// Session expired
    SessionExpired,
    
    /// Quota exceeded
    QuotaExceeded,
};

/// Failure reasons for telemetry
pub const FailureReason = enum {
    timeout,
    authentication_failed,
    transport_error,
    protocol_violation,
    key_rotation_timeout,
    session_expired,
};
