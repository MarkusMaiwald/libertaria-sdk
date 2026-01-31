//! RFC-0121: Slash Protocol - Detection and Punishment
//!
//! Defines the SlashSignal structure and verification logic for active defense.

const std = @import("std");
const crypto = @import("std").crypto;

/// Reason for the slash
pub const SlashReason = enum(u8) {
    BetrayalNegativeCycle = 0x01, // Bellman-Ford detection
    DoubleSign = 0x02, // Equivocation
    InvalidProof = 0x03, // Forged check
    Spam = 0x04, // DoS attempt (L0 triggered)
};

/// Type of punishment requested
pub const PunishmentType = enum(u8) {
    Quarantine = 0x01, // Temporary isolation (honeypot)
    ReputationSlash = 0x02, // Degradation of trust score
    Exile = 0x03, // Permanent ban + Bond burning (L3)
};

/// A cryptographic signal announcing a detected betrayal
pub const SlashSignal = struct {
    target_did: [32]u8,
    reason: SlashReason,
    punishment: PunishmentType,
    evidence_hash: [32]u8, // Hash of the proof (or full proof if small)
    timestamp: i64,
    nonce: u64,

    /// Serialize to bytes for signing (excluding signature)
    pub fn serializeForSigning(self: SlashSignal) [82]u8 {
        var buf: [82]u8 = undefined;
        // Target DID (32)
        @memcpy(buf[0..32], &self.target_did);
        // Reason (1)
        buf[32] = @intFromEnum(self.reason);
        // Punishment (1)
        buf[33] = @intFromEnum(self.punishment);
        // Evidence Hash (32)
        @memcpy(buf[34..66], &self.evidence_hash);
        // Timestamp (8)
        std.mem.writeInt(i64, buf[66..74], self.timestamp, .little);
        // Nonce (8)
        std.mem.writeInt(u64, buf[74..82], self.nonce, .little);
        return buf;
    }
};

test "slash signal serialization" {
    const signal = SlashSignal{
        .target_did = [_]u8{1} ** 32,
        .reason = .BetrayalNegativeCycle,
        .punishment = .Quarantine,
        .evidence_hash = [_]u8{0xAA} ** 32,
        .timestamp = 1000,
        .nonce = 42,
    };

    const bytes = signal.serializeForSigning();
    try std.testing.expectEqual(bytes[0], 1);
    try std.testing.expectEqual(bytes[32], 0x01); // Reason
    try std.testing.expectEqual(bytes[33], 0x01); // Punishment
    try std.testing.expectEqual(bytes[34], 0xAA); // Evidence
}
