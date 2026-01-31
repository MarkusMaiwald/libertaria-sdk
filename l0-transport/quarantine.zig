//! Quarantine List - Active Defense Enforcement
//!
//! Maintains a list of locally blocked/monitored DIDs based on SlashSignals.

const std = @import("std");

/// Status of a quarantined node
pub const QuarantineStatus = enum {
    None, // Not quarantined
    Blocked, // Drop all traffic
    Honeypot, // Accept traffic, log analysis, send fake OKs?
};

pub const QuarantineEntry = struct {
    until_ts: i64,
    mode: QuarantineStatus,
    reason: u8,
};

/// High-performance blocking list
pub const QuarantineList = struct {
    allocator: std.mem.Allocator,
    // Using u256 to represent [32]u8 DID as key for HashMap
    lookup: std.AutoHashMap(u256, QuarantineEntry),

    pub fn init(allocator: std.mem.Allocator) QuarantineList {
        return QuarantineList{
            .allocator = allocator,
            .lookup = std.AutoHashMap(u256, QuarantineEntry).init(allocator),
        };
    }

    pub fn deinit(self: *QuarantineList) void {
        self.lookup.deinit();
    }

    /// Add a node to quarantine
    pub fn add(self: *QuarantineList, did: [32]u8, mode: QuarantineStatus, duration_sec: i64, reason: u8) !void {
        const key = std.mem.readInt(u256, &did, .little);
        const now = std.time.timestamp();

        const entry = QuarantineEntry{
            .until_ts = now + duration_sec,
            .mode = mode,
            .reason = reason,
        };

        try self.lookup.put(key, entry);
    }

    /// Check status of a node
    pub fn check(self: *const QuarantineList, did: [32]u8) QuarantineStatus {
        const key = std.mem.readInt(u256, &did, .little);
        if (self.lookup.get(key)) |entry| {
            const now = std.time.timestamp();
            if (now > entry.until_ts) {
                // Expired
                return .None;
            }
            return entry.mode;
        }
        return .None;
    }
};

test "quarantine list basic" {
    var list = QuarantineList.init(std.testing.allocator);
    defer list.deinit();

    // Valid hex for u8 (0xBB)
    const bad_did = [_]u8{0xBB} ** 32;
    try list.add(bad_did, .Blocked, 3600, 1);

    try std.testing.expectEqual(QuarantineStatus.Blocked, list.check(bad_did));

    const good_did = [_]u8{0xAA} ** 32;
    try std.testing.expectEqual(QuarantineStatus.None, list.check(good_did));
}
