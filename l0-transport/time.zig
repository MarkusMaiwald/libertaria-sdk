//! Sovereign Time Protocol (RFC-0105)
//!
//! Time is a first-class sovereign dimension in Libertaria.
//! No rollover for 10^21 years. Event-driven, not tick-based.
//!
//! Core type: u128 attoseconds since anchor epoch.
//! Kenya-optimized: u64 nanoseconds for storage.

const std = @import("std");

// ============================================================================
// CONSTANTS
// ============================================================================

/// Attoseconds per time unit
pub const ATTOSECONDS_PER_FEMTOSECOND: u128 = 1_000;
pub const ATTOSECONDS_PER_PICOSECOND: u128 = 1_000_000;
pub const ATTOSECONDS_PER_NANOSECOND: u128 = 1_000_000_000;
pub const ATTOSECONDS_PER_MICROSECOND: u128 = 1_000_000_000_000;
pub const ATTOSECONDS_PER_MILLISECOND: u128 = 1_000_000_000_000_000;
pub const ATTOSECONDS_PER_SECOND: u128 = 1_000_000_000_000_000_000;

/// Drift tolerance for Kenya devices (30 seconds)
pub const KENYA_DRIFT_TOLERANCE_AS: u128 = 30 * ATTOSECONDS_PER_SECOND;

/// Maximum future timestamp acceptance (1 hour)
pub const MAX_FUTURE_AS: u128 = 3630 * ATTOSECONDS_PER_SECOND;

/// Maximum age for vectors (30 days)
pub const MAX_AGE_AS: u128 = 30 * 24 * 3600 * ATTOSECONDS_PER_SECOND;

// ============================================================================
// ANCHOR EPOCH
// ============================================================================

/// Anchor epoch type for timestamp interpretation
pub const AnchorEpoch = enum(u8) {
    /// System boot (monotonic, default for local operations)
    system_boot = 0,
    /// Mission launch (for probes/long-term deployments)
    mission_epoch = 1,
    /// Unix epoch 1970-01-01T00:00:00Z (for interoperability)
    unix_1970 = 2,
    /// Bitcoin genesis block 2009-01-03T18:15:05Z (objective truth)
    bitcoin_genesis = 3,
    /// GPS epoch 1980-01-06T00:00:00Z (for precision timing)
    gps_epoch = 4,

    /// Bitcoin genesis in Unix seconds
    pub const BITCOIN_GENESIS_UNIX: u64 = 1231006505;

    /// GPS epoch in Unix seconds
    pub const GPS_EPOCH_UNIX: u64 = 315964800;

    /// Convert between epochs
    pub fn toUnixOffset(self: AnchorEpoch) i128 {
        return switch (self) {
            .system_boot => 0, // Unknown offset
            .mission_epoch => 0, // Mission-specific
            .unix_1970 => 0,
            .bitcoin_genesis => @as(i128, BITCOIN_GENESIS_UNIX) * @as(i128, ATTOSECONDS_PER_SECOND),
            .gps_epoch => @as(i128, GPS_EPOCH_UNIX) * @as(i128, ATTOSECONDS_PER_SECOND),
        };
    }
};

// ============================================================================
// SOVEREIGN TIMESTAMP
// ============================================================================

/// Sovereign timestamp: u128 attoseconds since anchor epoch
/// Covers 10^21 years (beyond heat death of universe)
///
/// Wire format: 17 bytes (16 for u128 + 1 for anchor)
pub const SovereignTimestamp = struct {
    /// Raw attoseconds value
    raw: u128,

    /// Anchor epoch type
    anchor: AnchorEpoch,

    pub const SERIALIZED_SIZE = 17;

    /// Create from raw attoseconds
    pub fn fromAttoseconds(as: u128, anchor: AnchorEpoch) SovereignTimestamp {
        return .{ .raw = as, .anchor = anchor };
    }

    /// Create from nanoseconds (common hardware precision)
    pub fn fromNanoseconds(ns: u64, anchor: AnchorEpoch) SovereignTimestamp {
        return .{
            .raw = @as(u128, ns) * ATTOSECONDS_PER_NANOSECOND,
            .anchor = anchor,
        };
    }

    /// Create from microseconds
    pub fn fromMicroseconds(us: u64, anchor: AnchorEpoch) SovereignTimestamp {
        return .{
            .raw = @as(u128, us) * ATTOSECONDS_PER_MICROSECOND,
            .anchor = anchor,
        };
    }

    /// Create from milliseconds
    pub fn fromMilliseconds(ms: u64, anchor: AnchorEpoch) SovereignTimestamp {
        return .{
            .raw = @as(u128, ms) * ATTOSECONDS_PER_MILLISECOND,
            .anchor = anchor,
        };
    }

    /// Create from seconds
    pub fn fromSeconds(s: u64, anchor: AnchorEpoch) SovereignTimestamp {
        return .{
            .raw = @as(u128, s) * ATTOSECONDS_PER_SECOND,
            .anchor = anchor,
        };
    }

    /// Create from Unix timestamp (seconds since 1970)
    pub fn fromUnixSeconds(unix_s: u64) SovereignTimestamp {
        return fromSeconds(unix_s, .unix_1970);
    }

    /// Create from Unix timestamp (milliseconds since 1970)
    pub fn fromUnixMillis(unix_ms: u64) SovereignTimestamp {
        return fromMilliseconds(unix_ms, .unix_1970);
    }

    /// Get current time (platform-specific)
    pub fn now() SovereignTimestamp {
        // Use std.time for now, HAL will override
        const ns = @as(u64, @intCast(std.time.nanoTimestamp()));
        return fromNanoseconds(ns, .system_boot);
    }

    /// Convert to nanoseconds (may lose precision for very large values)
    pub fn toNanoseconds(self: SovereignTimestamp) u128 {
        return self.raw / ATTOSECONDS_PER_NANOSECOND;
    }

    /// Convert to microseconds
    pub fn toMicroseconds(self: SovereignTimestamp) u128 {
        return self.raw / ATTOSECONDS_PER_MICROSECOND;
    }

    /// Convert to milliseconds
    pub fn toMilliseconds(self: SovereignTimestamp) u128 {
        return self.raw / ATTOSECONDS_PER_MILLISECOND;
    }

    /// Convert to seconds
    pub fn toSeconds(self: SovereignTimestamp) u128 {
        return self.raw / ATTOSECONDS_PER_SECOND;
    }

    /// Convert to Unix timestamp (seconds since 1970)
    /// Only valid if anchor is unix_1970 or bitcoin_genesis
    pub fn toUnixSeconds(self: SovereignTimestamp) ?u64 {
        const seconds = switch (self.anchor) {
            .unix_1970 => self.raw / ATTOSECONDS_PER_SECOND,
            .bitcoin_genesis => blk: {
                const as_since_unix = self.raw + @as(u128, AnchorEpoch.BITCOIN_GENESIS_UNIX) * ATTOSECONDS_PER_SECOND;
                break :blk as_since_unix / ATTOSECONDS_PER_SECOND;
            },
            else => return null,
        };
        if (seconds > std.math.maxInt(u64)) return null;
        return @intCast(seconds);
    }

    /// Duration between two timestamps (signed)
    pub fn diff(self: SovereignTimestamp, other: SovereignTimestamp) i128 {
        // Handle the subtraction carefully to avoid overflow
        if (self.raw >= other.raw) {
            const delta = self.raw - other.raw;
            // Cap at i128 max if too large
            if (delta > @as(u128, std.math.maxInt(i128))) {
                return std.math.maxInt(i128);
            }
            return @intCast(delta);
        } else {
            const delta = other.raw - self.raw;
            // Cap at i128 min if too large
            if (delta > @as(u128, std.math.maxInt(i128)) + 1) {
                return std.math.minInt(i128);
            }
            return -@as(i128, @intCast(delta));
        }
    }

    /// Duration since another timestamp (unsigned, assumes self > other)
    pub fn since(self: SovereignTimestamp, other: SovereignTimestamp) u128 {
        if (self.raw >= other.raw) {
            return self.raw - other.raw;
        }
        return 0;
    }

    /// Check if this timestamp is after another
    pub fn isAfter(self: SovereignTimestamp, other: SovereignTimestamp) bool {
        return self.raw > other.raw;
    }

    /// Check if this timestamp is before another
    pub fn isBefore(self: SovereignTimestamp, other: SovereignTimestamp) bool {
        return self.raw < other.raw;
    }

    /// Add duration (attoseconds) - saturating
    pub fn add(self: SovereignTimestamp, duration_as: u128) SovereignTimestamp {
        return .{
            .raw = self.raw +| duration_as, // Saturating add
            .anchor = self.anchor,
        };
    }

    /// Add seconds
    pub fn addSeconds(self: SovereignTimestamp, seconds: u64) SovereignTimestamp {
        return self.add(@as(u128, seconds) * ATTOSECONDS_PER_SECOND);
    }

    /// Subtract duration (attoseconds) - saturating
    pub fn sub(self: SovereignTimestamp, duration_as: u128) SovereignTimestamp {
        return .{
            .raw = self.raw -| duration_as, // Saturating sub
            .anchor = self.anchor,
        };
    }

    /// Check if timestamp is within acceptable drift for vectors
    pub fn isWithinDrift(self: SovereignTimestamp, reference: SovereignTimestamp, drift_tolerance: u128) bool {
        const delta = if (self.raw >= reference.raw)
            self.raw - reference.raw
        else
            reference.raw - self.raw;
        return delta <= drift_tolerance;
    }

    /// Validate timestamp is not too far in future or too old
    pub fn validateForVector(self: SovereignTimestamp, current: SovereignTimestamp) ValidationResult {
        if (self.raw > current.raw + MAX_FUTURE_AS) {
            return .too_far_future;
        }
        if (current.raw > self.raw + MAX_AGE_AS) {
            return .too_old;
        }
        return .valid;
    }

    pub const ValidationResult = enum {
        valid,
        too_far_future,
        too_old,
    };

    /// Serialize to wire format (17 bytes)
    pub fn serialize(self: SovereignTimestamp) [SERIALIZED_SIZE]u8 {
        var buf: [SERIALIZED_SIZE]u8 = undefined;
        // u128 as two u64s (little-endian)
        const low: u64 = @truncate(self.raw);
        const high: u64 = @truncate(self.raw >> 64);
        std.mem.writeInt(u64, buf[0..8], low, .little);
        std.mem.writeInt(u64, buf[8..16], high, .little);
        buf[16] = @intFromEnum(self.anchor);
        return buf;
    }

    /// Deserialize from wire format
    pub fn deserialize(data: *const [SERIALIZED_SIZE]u8) SovereignTimestamp {
        const low = std.mem.readInt(u64, data[0..8], .little);
        const high = std.mem.readInt(u64, data[8..16], .little);
        const raw = (@as(u128, high) << 64) | @as(u128, low);
        return .{
            .raw = raw,
            .anchor = @enumFromInt(data[16]),
        };
    }
};

// ============================================================================
// SOVEREIGN EPOCH
// ============================================================================

/// Standard Epoch Duration (1 Hour)
/// Used for Key Rotation, Session Renewal, and Cron synchronization.
pub const EPOCH_DURATION_AS: u128 = 3600 * ATTOSECONDS_PER_SECOND;

/// A Sovereign Epoch represents a fixed time slice in the timeline.
pub const Epoch = struct {
    /// Sequential index of the epoch since Anchor
    index: u64,

    /// Get the epoch containing a specific timestamp
    pub fn fromTimestamp(ts: SovereignTimestamp) Epoch {
        // We calculate epoch relative to the generic timeline raw value
        // Note: This implies different anchors might align epochs differently unless normalized.
        // For simplicity, we define Epoch 0 starts at raw=0.
        const idx = @as(u64, @intCast(ts.raw / EPOCH_DURATION_AS));
        return .{ .index = idx };
    }

    /// Get current epoch
    pub fn current() Epoch {
        return fromTimestamp(SovereignTimestamp.now());
    }

    /// Get start timestamp of this epoch
    pub fn startTime(self: Epoch, anchor: AnchorEpoch) SovereignTimestamp {
        return SovereignTimestamp.fromAttoseconds(@as(u128, self.index) * EPOCH_DURATION_AS, anchor);
    }

    /// Get end timestamp of this epoch (exclusive)
    pub fn endTime(self: Epoch, anchor: AnchorEpoch) SovereignTimestamp {
        return SovereignTimestamp.fromAttoseconds(@as(u128, self.index + 1) * EPOCH_DURATION_AS, anchor);
    }

    /// Get duration until next epoch start (for sleep/cron)
    pub fn timeRemaining(self: Epoch, current_ts: SovereignTimestamp) Duration {
        const end_ts = self.endTime(current_ts.anchor);
        return Duration.fromAttoseconds(end_ts.since(current_ts));
    }

    /// Check if a timestamp is within this epoch
    pub fn contains(self: Epoch, ts: SovereignTimestamp) bool {
        const other_idx = @as(u64, @intCast(ts.raw / EPOCH_DURATION_AS));
        return self.index == other_idx;
    }

    /// Get next epoch
    pub fn next(self: Epoch) Epoch {
        return .{ .index = self.index + 1 };
    }

    /// Get previous epoch
    pub fn prev(self: Epoch) Epoch {
        if (self.index == 0) return self;
        return .{ .index = self.index - 1 };
    }
};

// ============================================================================
// COMPACT TIMESTAMP (Kenya Optimization)
// ============================================================================

/// Kenya-optimized timestamp storage (9 bytes vs 17)
/// Uses nanoseconds instead of attoseconds (good for ~584 years)
pub const CompactTimestamp = packed struct {
    /// Nanoseconds since anchor
    ns: u64,
    /// Anchor epoch
    anchor: AnchorEpoch,

    pub const SERIALIZED_SIZE = 9;

    /// Convert from SovereignTimestamp (loses sub-nanosecond precision)
    pub fn fromSovereign(ts: SovereignTimestamp) CompactTimestamp {
        const ns = ts.raw / ATTOSECONDS_PER_NANOSECOND;
        return .{
            .ns = if (ns > std.math.maxInt(u64)) std.math.maxInt(u64) else @intCast(ns),
            .anchor = ts.anchor,
        };
    }

    /// Convert to SovereignTimestamp
    pub fn toSovereign(self: CompactTimestamp) SovereignTimestamp {
        return SovereignTimestamp.fromNanoseconds(self.ns, self.anchor);
    }

    /// Serialize to wire format (9 bytes)
    pub fn serialize(self: CompactTimestamp) [SERIALIZED_SIZE]u8 {
        var buf: [SERIALIZED_SIZE]u8 = undefined;
        std.mem.writeInt(u64, buf[0..8], self.ns, .little);
        buf[8] = @intFromEnum(self.anchor);
        return buf;
    }

    /// Deserialize from wire format
    pub fn deserialize(data: *const [SERIALIZED_SIZE]u8) CompactTimestamp {
        return .{
            .ns = std.mem.readInt(u64, data[0..8], .little),
            .anchor = @enumFromInt(data[8]),
        };
    }
};

// ============================================================================
// DURATION TYPE
// ============================================================================

/// Duration in attoseconds (for intervals, timeouts)
pub const Duration = struct {
    as: u128,

    pub fn fromAttoseconds(as: u128) Duration {
        return .{ .as = as };
    }

    pub fn fromNanoseconds(ns: u64) Duration {
        return .{ .as = @as(u128, ns) * ATTOSECONDS_PER_NANOSECOND };
    }

    pub fn fromMicroseconds(us: u64) Duration {
        return .{ .as = @as(u128, us) * ATTOSECONDS_PER_MICROSECOND };
    }

    pub fn fromMilliseconds(ms: u64) Duration {
        return .{ .as = @as(u128, ms) * ATTOSECONDS_PER_MILLISECOND };
    }

    pub fn fromSeconds(s: u64) Duration {
        return .{ .as = @as(u128, s) * ATTOSECONDS_PER_SECOND };
    }

    pub fn fromMinutes(m: u64) Duration {
        return fromSeconds(m * 60);
    }

    pub fn fromHours(h: u64) Duration {
        return fromSeconds(h * 3600);
    }

    pub fn fromDays(d: u64) Duration {
        return fromSeconds(d * 86400);
    }

    pub fn fromYears(y: u64) Duration {
        // Gregorian average: 365.2425 days
        return fromSeconds(y * 31556952);
    }

    /// 1 million years (probe hibernation test)
    pub fn oneMillionYears() Duration {
        return fromYears(1_000_000);
    }

    pub fn toNanoseconds(self: Duration) u128 {
        return self.as / ATTOSECONDS_PER_NANOSECOND;
    }

    pub fn toSeconds(self: Duration) u128 {
        return self.as / ATTOSECONDS_PER_SECOND;
    }
};

// ============================================================================
// TESTS
// ============================================================================

test "SovereignTimestamp: basic creation" {
    const ts = SovereignTimestamp.fromSeconds(1000, .unix_1970);
    try std.testing.expectEqual(@as(u128, 1000) * ATTOSECONDS_PER_SECOND, ts.raw);
    try std.testing.expectEqual(AnchorEpoch.unix_1970, ts.anchor);
}

test "SovereignTimestamp: unit conversions" {
    const ts = SovereignTimestamp.fromSeconds(60, .unix_1970);

    try std.testing.expectEqual(@as(u128, 60), ts.toSeconds());
    try std.testing.expectEqual(@as(u128, 60_000), ts.toMilliseconds());
    try std.testing.expectEqual(@as(u128, 60_000_000), ts.toMicroseconds());
    try std.testing.expectEqual(@as(u128, 60_000_000_000), ts.toNanoseconds());
}

test "SovereignTimestamp: comparison" {
    const ts1 = SovereignTimestamp.fromSeconds(100, .unix_1970);
    const ts2 = SovereignTimestamp.fromSeconds(200, .unix_1970);

    try std.testing.expect(ts2.isAfter(ts1));
    try std.testing.expect(ts1.isBefore(ts2));
    try std.testing.expectEqual(@as(i128, -100) * @as(i128, ATTOSECONDS_PER_SECOND), ts1.diff(ts2));
}

test "SovereignTimestamp: arithmetic" {
    const ts1 = SovereignTimestamp.fromSeconds(100, .unix_1970);
    const ts2 = ts1.addSeconds(50);

    try std.testing.expectEqual(@as(u128, 150), ts2.toSeconds());

    const ts3 = ts2.sub(25 * ATTOSECONDS_PER_SECOND);
    try std.testing.expectEqual(@as(u128, 125), ts3.toSeconds());
}

test "SovereignTimestamp: serialization roundtrip" {
    const original = SovereignTimestamp.fromSeconds(1706652000, .bitcoin_genesis);
    const serialized = original.serialize();
    const deserialized = SovereignTimestamp.deserialize(&serialized);

    try std.testing.expectEqual(original.raw, deserialized.raw);
    try std.testing.expectEqual(original.anchor, deserialized.anchor);
}

test "SovereignTimestamp: unix conversion" {
    const ts = SovereignTimestamp.fromUnixSeconds(1706652000);
    const unix = ts.toUnixSeconds();

    try std.testing.expect(unix != null);
    try std.testing.expectEqual(@as(u64, 1706652000), unix.?);
}

test "CompactTimestamp: conversion roundtrip" {
    const original = SovereignTimestamp.fromSeconds(1000, .unix_1970);
    const compact = CompactTimestamp.fromSovereign(original);
    const restored = compact.toSovereign();

    // Should match at nanosecond precision
    try std.testing.expectEqual(original.toNanoseconds(), restored.toNanoseconds());
}

test "CompactTimestamp: serialization roundtrip" {
    const original = CompactTimestamp{
        .ns = 1706652000_000_000_000,
        .anchor = .unix_1970,
    };
    const serialized = original.serialize();
    const deserialized = CompactTimestamp.deserialize(&serialized);

    try std.testing.expectEqual(original.ns, deserialized.ns);
    try std.testing.expectEqual(original.anchor, deserialized.anchor);
}

test "Duration: one million years" {
    const d = Duration.oneMillionYears();

    // Verify it fits in u128
    try std.testing.expect(d.as > 0);

    // ~3.15576e31 attoseconds
    const expected_as: u128 = 1_000_000 * 31556952 * ATTOSECONDS_PER_SECOND;
    try std.testing.expectEqual(expected_as, d.as);

    // Verify u128 has plenty of headroom
    const u128_max: u128 = std.math.maxInt(u128);
    try std.testing.expect(d.as < u128_max / 1_000_000); // Could store 1e6 more!
}

test "SovereignTimestamp: validation" {
    const now = SovereignTimestamp.fromSeconds(1706652000, .unix_1970);

    // Valid: within bounds
    const valid = SovereignTimestamp.fromSeconds(1706651000, .unix_1970);
    try std.testing.expectEqual(SovereignTimestamp.ValidationResult.valid, valid.validateForVector(now));

    // Too far in future (> 1 hour)
    const future = now.addSeconds(7200);
    try std.testing.expectEqual(SovereignTimestamp.ValidationResult.too_far_future, future.validateForVector(now));

    // Too old (> 30 days)
    const old = now.sub(31 * 24 * 3600 * ATTOSECONDS_PER_SECOND);
    try std.testing.expectEqual(SovereignTimestamp.ValidationResult.too_old, old.validateForVector(now));
}

test "Epoch: calculation" {
    // 1 Hour = 3600 seconds
    const t0 = SovereignTimestamp.fromSeconds(0, .unix_1970);
    const e0 = Epoch.fromTimestamp(t0);
    try std.testing.expectEqual(@as(u64, 0), e0.index);

    const t1 = SovereignTimestamp.fromSeconds(3599, .unix_1970);
    const e1 = Epoch.fromTimestamp(t1);
    try std.testing.expectEqual(@as(u64, 0), e1.index);

    const t2 = SovereignTimestamp.fromSeconds(3600, .unix_1970);
    const e2 = Epoch.fromTimestamp(t2);
    try std.testing.expectEqual(@as(u64, 1), e2.index);

    // Remaining time
    const rem = e0.timeRemaining(t1);
    try std.testing.expectEqual(@as(u128, 1) * ATTOSECONDS_PER_SECOND, rem.as);
}
