//! L2 Membrane - Policy Engine
//!
//! " The Membrane decides what enters the Cell. "
//!
//! Responsibilities:
//! 1. Packet Classification (Service Type Analysis)
//! 2. Traffic Shaping (Priority Queues)
//! 3. Reputation Enforcement (Source Verification)
//! 4. DoS Mitigation (Entropy Verification)
//!
//! Implementation: High-performance Zig (Hardware-close).

const std = @import("std");
const lwf = @import("lwf");

pub const PolicyDecision = enum {
    drop, // Silently discard
    reject, // Send NACK/Error
    forward, // Normal processing
    prioritize, // Jump the queue
    throttle, // Delay processing
};

pub const PolicyReason = enum {
    none,
    invalid_header,
    insufficient_entropy,
    reputation_too_low,
    congestion_control,
    policy_allow,
    service_priority,
    service_bulk,
};

pub const PolicyEngine = struct {
    allocator: std.mem.Allocator,

    // Configuration
    min_entropy_difficulty: u8,
    require_encryption: bool,

    pub fn init(allocator: std.mem.Allocator) PolicyEngine {
        return .{
            .allocator = allocator,
            .min_entropy_difficulty = 8, // Baseline
            .require_encryption = true,
        };
    }

    /// fastDecide: O(1) decision based purely on Header
    /// Used by Switch/Router for "Fast Drop"
    pub fn decide(self: *const PolicyEngine, header: *const lwf.LWFHeader) PolicyDecision {
        // 1. Basic Validity
        if (!header.isValid()) return .drop;

        // 2. Entropy Check (DoS Defense)
        // If flag is set, actual verification happens later (expensive).
        // Here we check if the CLAIMED difficulty meets our minimum.
        if (header.entropy_difficulty < self.min_entropy_difficulty) {
            // Exceptions: Microframes / Trusted flows might allow 0
            if (header.frame_class != @intFromEnum(lwf.FrameClass.micro)) {
                return .drop;
            }
        }

        // 3. Service-Based Classification
        switch (header.service_type) {
            // Streaming (High Priority)
            lwf.LWFHeader.ServiceType.STREAM_AUDIO, lwf.LWFHeader.ServiceType.STREAM_VIDEO, lwf.LWFHeader.ServiceType.STREAM_DATA => {
                return .prioritize;
            },

            // Swarm (Low Priority)
            lwf.LWFHeader.ServiceType.SWARM_MANIFEST, lwf.LWFHeader.ServiceType.SWARM_HAVE, lwf.LWFHeader.ServiceType.SWARM_REQUEST, lwf.LWFHeader.ServiceType.SWARM_BLOCK => {
                return .throttle; // Default to Bulk behavior
            },

            // Feed Social (Mandatory Encryption)
            0x0A00...0x0AFF => {
                if (header.flags & lwf.LWFFlags.ENCRYPTED == 0) {
                    return .drop; // Policy Violation
                }
                return .forward;
            },

            // Default
            else => return .forward,
        }
    }

    /// assessReputation: O(log N) lookup in QVL
    /// Returns decision based on Source Hint
    pub fn assessReputation(self: *PolicyEngine, source_hint: [24]u8) PolicyDecision {
        _ = self;
        _ = source_hint;
        // TODO: Interface with QVL Trust Graph
        // Lookup source_hint -> Reputation Score (0.0 - 1.0)
        // If Score < 0.2 -> .drop
        // If Score > 0.8 -> .prioritize

        return .forward; // Mock
    }
};

test "PolicyEngine: Classification rules" {
    const allocator = std.testing.allocator;
    const engine = PolicyEngine.init(allocator);

    var header = lwf.LWFHeader.init();

    // Case 1: Stream -> Prioritize
    header.service_type = lwf.LWFHeader.ServiceType.STREAM_VIDEO;
    header.entropy_difficulty = 10;
    try std.testing.expectEqual(PolicyDecision.prioritize, engine.decide(&header));

    // Case 2: Swarm -> Throttle
    header.service_type = lwf.LWFHeader.ServiceType.SWARM_BLOCK;
    try std.testing.expectEqual(PolicyDecision.throttle, engine.decide(&header));

    // Case 3: Low Entropy -> Drop
    header.service_type = lwf.LWFHeader.ServiceType.DATA_TRANSPORT;
    header.entropy_difficulty = 0;
    // But wait, FrameClass default is Standard. min_entropy is 8.
    try std.testing.expectEqual(PolicyDecision.drop, engine.decide(&header));

    // Case 4: Microframe (High Entropy cost exempt?)
    header.frame_class = @intFromEnum(lwf.FrameClass.micro);
    header.flags = 0; // No entropy
    // decide checks difficulty < min. 0 < 8.
    // Exception logic for micro?
    // Code says: if micro, OK.
    try std.testing.expectEqual(PolicyDecision.forward, engine.decide(&header)); // Forward (Default)
}
