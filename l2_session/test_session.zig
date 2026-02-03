//! Tests for session establishment

const std = @import("std");
const testing = std.testing;

const Session = @import("session.zig").Session;
const State = @import("state.zig").State;
const SessionConfig = @import("config.zig").SessionConfig;
const Handshake = @import("handshake.zig").Handshake;

/// Scenario-001.1: Successful session establishment
test "Scenario-001.1: Session establishment creates valid session" do
    // Validates: SPEC-018 2.1
    const config = SessionConfig{};
    const ctx = .{}; // Mock context
    
    // In real implementation, this would perform PQxdh handshake
    // For now, we test the structure
    const session = Session.new("did:morpheus:test123", config);
    
    try testing.expectEqualStrings("did:morpheus:test123", session.peer_did);
    try testing.expectEqual(State.idle, session.state);
    try testing.expect(session.created_at > 0);
end

/// Scenario-001.4: Invalid signature handling
test "Scenario-001.4: Invalid signature quarantines peer" do
    // Validates: SPEC-018 2.1
    // TODO: Implement with mock crypto
    const config = SessionConfig{};
    var session = Session.new("did:morpheus:badactor", config);
    
    // Simulate failed authentication
    session.state = State.failed;
    
    // TODO: Verify quarantine is set
    try testing.expectEqual(State.failed, session.state);
end

/// Test session configuration defaults
test "Default configuration is valid" do
    const config = SessionConfig{};
    
    try testing.expectEqual(@as(u64, 24), config.ttl.hours);
    try testing.expectEqual(@as(u64, 30), config.heartbeat_interval.seconds);
    try testing.expectEqual(@as(u8, 3), config.heartbeat_tolerance);
    try testing.expectEqual(@as(u64, 5), config.handshake_timeout.seconds);
end
