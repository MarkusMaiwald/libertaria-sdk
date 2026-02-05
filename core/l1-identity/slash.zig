//! RFC-0121: Slash Protocol Core
//!
//! Definition of the "Death Sentence" signal and packet format.

const std = @import("std");

/// RFC-0121: Reasons for punishment
pub const SlashReason = enum(u8) {
    BetrayalCycle = 0x01, // Bellman-Ford negative cycle
    SybilCluster = 0x02, // BP anomaly score >0.8
    ReplayAttack = 0x03, // Duplicate entropy stamps
    EclipseAttempt = 0x04, // Gossip coverage <20%
    CoordinatedFlood = 0x05, // Rate limit violation
    InvalidProof = 0x06, // Tampered PoP
};

/// RFC-0121: Severity Levels (u8 for extern compatibility)
pub const SlashSeverity = enum(u8) {
    Warn = 0, // Log only; no enforcement
    Quarantine = 1, // Honeypot mode
    Slash = 2, // Rate limit + reputation hit
    Exile = 3, // Permanent block + economic burn
};

/// RFC-0121: The Slash Signal Payload (82 bytes)
/// Extern struct for C-compatible layout (no bit-packing)
pub const SlashSignal = extern struct {
    // Target identification (32 bytes)
    target_did: [32]u8,

    // Evidence (41 bytes)
    reason: SlashReason, // 1 byte
    evidence_hash: [32]u8, // 32 bytes
    timestamp: u64, // 8 bytes

    // Enforcement parameters (9 bytes)
    severity: SlashSeverity, // 1 byte
    duration_seconds: u32, // 4 bytes
    entropy_stamp: u32, // 4 bytes

    pub fn serializeForSigning(self: SlashSignal) [82]u8 {
        var buf: [82]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();
        // Ignore errors (buffer is exact size)
        writer.writeAll(&self.target_did) catch {};
        writer.writeInt(u8, @intFromEnum(self.reason), .little) catch {};
        writer.writeAll(&self.evidence_hash) catch {};
        writer.writeInt(u64, self.timestamp, .little) catch {};
        writer.writeInt(u8, @intFromEnum(self.severity), .little) catch {};
        writer.writeInt(u32, self.duration_seconds, .little) catch {};
        writer.writeInt(u32, self.entropy_stamp, .little) catch {};
        return buf;
    }
};

/// RFC-0121: The Full Slash Packet (Signed)
pub const SlashPacket = struct {
    signal: SlashSignal,
    signature: [64]u8, // Ed25519 signature of signal hash

    /// Calculate hash of the inner signal
    pub fn hash(self: *const SlashPacket) [32]u8 {
        var hasher = std.crypto.hash.Blake3.init(.{});
        const bytes = std.mem.asBytes(&self.signal);
        hasher.update(bytes);
        var out: [32]u8 = undefined;
        hasher.final(&out);
        return out;
    }
};

pub const PunishmentType = SlashSeverity; // Alias for backward compat if needed

test "SlashSignal serialization" {
    const signal = SlashSignal{
        .target_did = [_]u8{0xAA} ** 32,
        .reason = .BetrayalCycle,
        .evidence_hash = [_]u8{0xBB} ** 32,
        .timestamp = 123456789,
        .severity = .Quarantine,
        .duration_seconds = 3600,
        .entropy_stamp = 0xCAFEBABE,
    };

    const bytes = signal.serializeForSigning();
    try std.testing.expectEqual(82, bytes.len);
    try std.testing.expectEqual(0xAA, bytes[0]);
}
