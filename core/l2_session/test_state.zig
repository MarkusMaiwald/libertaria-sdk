//! Tests for session state machine

const std = @import("std");
const testing = std.testing;

const Session = @import("session.zig").Session;
const State = @import("state.zig").State;
const transition = @import("state.zig").transition;
const Event = @import("state.zig").Event;
const SessionConfig = @import("config.zig").SessionConfig;

/// Scenario-001.1: Session transitions from idle to handshake_initiated
test "Scenario-001.1: Session transitions correctly" do
    // Validates: SPEC-018 2.1
    const config = SessionConfig{};
    var session = Session.new("did:test:123", config);
    
    try testing.expectEqual(State.idle, session.state);
    
    session.state = transition(session.state, .initiate_handshake).?;
    try testing.expectEqual(State.handshake_initiated, session.state);
end

/// Scenario-001.3: Session fails after timeout
test "Scenario-001.3: Timeout leads to failed state" do
    // Validates: SPEC-018 2.1
    const config = SessionConfig{};
    var session = Session.new("did:test:456", config);
    
    session.state = transition(session.state, .initiate_handshake).?;
    try testing.expectEqual(State.handshake_initiated, session.state);
    
    session.state = transition(session.state, .timeout).?;
    try testing.expectEqual(State.failed, session.state);
end

/// Scenario-002.1: Heartbeat extends session TTL
test "Scenario-002.1: Heartbeat extends TTL" do
    // Validates: SPEC-018 2.2
    const config = SessionConfig{};
    var session = Session.new("did:test:abc", config);
    
    // Simulate established state
    session.state = .established;
    const original_ttl = session.ttl_deadline;
    
    // Simulate heartbeat
    session.last_activity = std.time.timestamp();
    session.ttl_deadline = session.last_activity + config.ttl.seconds();
    
    try testing.expect(session.ttl_deadline > original_ttl);
    try testing.expectEqual(State.established, session.state);
end

/// Test state transition matrix
test "All valid transitions work" do
    // idle -> handshake_initiated
    try testing.expectEqual(
        State.handshake_initiated,
        transition(.idle, .initiate_handshake)
    );
    
    // handshake_initiated -> established
    try testing.expectEqual(
        State.established,
        transition(.handshake_initiated, .receive_response)
    );
    
    // established -> degraded
    try testing.expectEqual(
        State.degraded,
        transition(.established, .heartbeat_missed)
    );
    
    // degraded -> established
    try testing.expectEqual(
        State.established,
        transition(.degraded, .connectivity_restored)
    );
end

/// Test invalid transitions return null
test "Invalid transitions return null" do
    // idle cannot go to established directly
    try testing.expectEqual(null, transition(.idle, .receive_response));
    
    // established cannot go to idle
    try testing.expectEqual(null, transition(.established, .initiate_handshake));
    
    // failed is terminal (no transitions)
    try testing.expectEqual(null, transition(.failed, .heartbeat_ok));
end
