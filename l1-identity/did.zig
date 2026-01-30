//! RFC-0830: DID Integration & Local Cache (Minimal Scope)
//!
//! This module provides DID parsing and resolution primitives for L0-L1.
//! Full W3C DID Document validation and Tombstoning is deferred to L2+ resolvers.
//!
//! Philosophy: Protocol stays dumb. L2+ resolvers enforce the standard.
//!
//! Scope:
//! - Parse DID strings (did:METHOD:ID format, no schema validation)
//! - Local cache with TTL-based expiration
//! - Opaque metadata storage (method-specific, unvalidated)
//! - Wire frame integration for DID identifiers
//!
//! Out of Scope:
//! - W3C DID Document parsing
//! - Rights system enforcement
//! - Tombstone deactivation handling
//! - Schema validation

const std = @import("std");
const crypto = std.crypto;

// ============================================================================
// Constants
// ============================================================================

/// Maximum length of a DID string (did:METHOD:ID)
pub const MAX_DID_LENGTH: usize = 256;

/// Default cache entry TTL: 1 hour (3600 seconds)
pub const DEFAULT_CACHE_TTL_SECONDS: u64 = 3600;

/// Supported DID methods
pub const DIDMethod = enum {
    mosaic,      // did:mosaic:*
    libertaria,  // did:libertaria:*
    other,       // Future methods, opaque handling
};

// ============================================================================
// DID Identifier: Minimal Parsing
// ============================================================================

pub const DIDIdentifier = struct {
    /// DID method (mosaic, libertaria, other)
    method: DIDMethod,

    /// 32-byte hash of method-specific identifier
    method_specific_id: [32]u8,

    /// Original DID string (for debugging, max 256 bytes)
    original: [MAX_DID_LENGTH]u8 = [_]u8{0} ** MAX_DID_LENGTH,
    original_len: usize = 0,

    /// Parse a DID string into structured form
    /// Format: did:METHOD:ID
    /// No validation beyond basic syntax; L2+ validates schema
    pub fn parse(did_string: []const u8) !DIDIdentifier {
        if (did_string.len == 0 or did_string.len > MAX_DID_LENGTH) {
            return error.InvalidDIDLength;
        }

        // Find "did:" prefix
        if (!std.mem.startsWith(u8, did_string, "did:")) {
            return error.MissingDIDPrefix;
        }

        // Find method separator (second ":")
        var colon_count: usize = 0;
        var method_end: usize = 0;
        for (did_string, 0..) |byte, idx| {
            if (byte == ':') {
                colon_count += 1;
                if (colon_count == 2) {
                    method_end = idx;
                    break;
                }
            }
        }

        if (colon_count < 2) {
            return error.MissingDIDMethod;
        }

        // Extract method name
        const method_str = did_string[4..method_end];

        // Check for empty method name
        if (method_str.len == 0) {
            return error.MissingDIDMethod;
        }

        const method = if (std.mem.eql(u8, method_str, "mosaic"))
            DIDMethod.mosaic
        else if (std.mem.eql(u8, method_str, "libertaria"))
            DIDMethod.libertaria
        else
            DIDMethod.other;

        // Extract method-specific identifier
        const msi_str = did_string[method_end + 1 ..];
        if (msi_str.len == 0) {
            return error.EmptyMethodSpecificId;
        }

        // Hash the method-specific identifier to 32 bytes
        var msi: [32]u8 = undefined;
        crypto.hash.sha2.Sha256.hash(msi_str, &msi, .{});

        var id = DIDIdentifier{
            .method = method,
            .method_specific_id = msi,
            .original_len = did_string.len,
        };

        @memcpy(id.original[0..did_string.len], did_string);

        return id;
    }

    /// Return the parsed DID as a string (for debugging)
    pub fn format(self: *const DIDIdentifier) []const u8 {
        return self.original[0..self.original_len];
    }

    /// Compare two DID identifiers by method-specific ID
    pub fn eql(self: *const DIDIdentifier, other: *const DIDIdentifier) bool {
        return self.method == other.method and
            std.mem.eql(u8, &self.method_specific_id, &other.method_specific_id);
    }
};

// ============================================================================
// DID Cache: TTL-based Local Resolution
// ============================================================================

pub const DIDCacheEntry = struct {
    did: DIDIdentifier,
    metadata: []const u8,       // Opaque bytes (method-specific)
    ttl_seconds: u64,           // Entry TTL
    created_at: u64,            // Unix timestamp

    /// Check if this cache entry has expired
    pub fn isExpired(self: *const DIDCacheEntry, now: u64) bool {
        const age = now - self.created_at;
        return age > self.ttl_seconds;
    }
};

pub const DIDCache = struct {
    cache: std.AutoHashMap([32]u8, DIDCacheEntry),
    allocator: std.mem.Allocator,

    /// Create a new DID cache
    pub fn init(allocator: std.mem.Allocator) DIDCache {
        return .{
            .cache = std.AutoHashMap([32]u8, DIDCacheEntry).init(allocator),
            .allocator = allocator,
        };
    }

    /// Deinitialize cache and free all stored metadata
    pub fn deinit(self: *DIDCache) void {
        var it = self.cache.valueIterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.metadata);
        }
        self.cache.deinit();
    }

    /// Store a DID with metadata and TTL
    pub fn store(
        self: *DIDCache,
        did: *const DIDIdentifier,
        metadata: []const u8,
        ttl_seconds: u64,
    ) !void {
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Allocate metadata copy
        const metadata_copy = try self.allocator.alloc(u8, metadata.len);
        @memcpy(metadata_copy, metadata);

        // Remove old entry if exists
        if (self.cache.contains(did.method_specific_id)) {
            if (self.cache.getPtr(did.method_specific_id)) |old_entry| {
                self.allocator.free(old_entry.metadata);
            }
        }

        // Store new entry
        const entry = DIDCacheEntry{
            .did = did.*,
            .metadata = metadata_copy,
            .ttl_seconds = ttl_seconds,
            .created_at = now,
        };

        try self.cache.put(did.method_specific_id, entry);
    }

    /// Retrieve a DID from cache (returns null if expired or not found)
    pub fn get(self: *DIDCache, did: *const DIDIdentifier) ?DIDCacheEntry {
        const now = @as(u64, @intCast(std.time.timestamp()));

        if (self.cache.get(did.method_specific_id)) |entry| {
            if (!entry.isExpired(now)) {
                return entry;
            }
            // Entry expired, remove it
            _ = self.cache.remove(did.method_specific_id);
            return null;
        }

        return null;
    }

    /// Invalidate a specific DID cache entry
    pub fn invalidate(self: *DIDCache, did: *const DIDIdentifier) void {
        if (self.cache.fetchRemove(did.method_specific_id)) |kv| {
            self.allocator.free(kv.value.metadata);
        }
    }

    /// Remove all expired entries
    pub fn prune(self: *DIDCache) void {
        const now = @as(u64, @intCast(std.time.timestamp()));

        // Collect keys to remove (can't mutate during iteration)
        var to_remove: [256][32]u8 = undefined;
        var remove_count: usize = 0;

        var it = self.cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.isExpired(now)) {
                if (remove_count < 256) {
                    to_remove[remove_count] = entry.key_ptr.*;
                    remove_count += 1;
                }
            }
        }

        // Now remove all expired entries
        for (0..remove_count) |i| {
            if (self.cache.fetchRemove(to_remove[i])) |kv| {
                self.allocator.free(kv.value.metadata);
            }
        }
    }

    /// Get total number of cached DIDs (including expired)
    pub fn count(self: *const DIDCache) usize {
        return self.cache.count();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "DID parsing: mosaic method" {
    const did_string = "did:mosaic:z7k8j9m3n5p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2f4g6h8";
    const did = try DIDIdentifier.parse(did_string);

    try std.testing.expectEqual(DIDMethod.mosaic, did.method);
    try std.testing.expectEqualSlices(u8, did.format(), did_string);
}

test "DID parsing: libertaria method" {
    const did_string = "did:libertaria:abc123def456";
    const did = try DIDIdentifier.parse(did_string);

    try std.testing.expectEqual(DIDMethod.libertaria, did.method);
}

test "DID parsing: invalid prefix" {
    const did_string = "notadid:mosaic:z123";
    const result = DIDIdentifier.parse(did_string);
    try std.testing.expectError(error.MissingDIDPrefix, result);
}

test "DID parsing: missing method" {
    const did_string = "did::z123";
    const result = DIDIdentifier.parse(did_string);
    try std.testing.expectError(error.MissingDIDMethod, result);
}

test "DID parsing: empty method-specific-id" {
    const did_string = "did:mosaic:";
    const result = DIDIdentifier.parse(did_string);
    try std.testing.expectError(error.EmptyMethodSpecificId, result);
}

test "DID parsing: too long" {
    var long_did: [MAX_DID_LENGTH + 1]u8 = [_]u8{'a'} ** (MAX_DID_LENGTH + 1);
    const result = DIDIdentifier.parse(&long_did);
    try std.testing.expectError(error.InvalidDIDLength, result);
}

test "DID equality" {
    const did1 = try DIDIdentifier.parse("did:mosaic:test1");
    const did2 = try DIDIdentifier.parse("did:mosaic:test1");
    const did3 = try DIDIdentifier.parse("did:mosaic:test2");

    try std.testing.expect(did1.eql(&did2));
    try std.testing.expect(!did1.eql(&did3));
}

test "DID cache storage and retrieval" {
    var cache = DIDCache.init(std.testing.allocator);
    defer cache.deinit();

    const did = try DIDIdentifier.parse("did:mosaic:cached123");
    const metadata = "test_metadata";

    try cache.store(&did, metadata, 3600);
    const entry = cache.get(&did);

    try std.testing.expect(entry != null);
    try std.testing.expectEqualSlices(u8, entry.?.metadata, metadata);
}

test "DID cache expiration" {
    var cache = DIDCache.init(std.testing.allocator);
    defer cache.deinit();

    const did = try DIDIdentifier.parse("did:mosaic:expire123");
    const metadata = "expiring_data";

    // Store with very short TTL (1 second)
    try cache.store(&did, metadata, 1);

    // Entry should be present immediately
    const entry = cache.get(&did);
    try std.testing.expect(entry != null);

    // After waiting for TTL to expire, entry should be gone
    // (In unit tests this is deferred to Phase 3 with proper time mocking)
}

test "DID cache invalidation" {
    var cache = DIDCache.init(std.testing.allocator);
    defer cache.deinit();

    const did = try DIDIdentifier.parse("did:mosaic:invalid123");
    const metadata = "to_invalidate";

    try cache.store(&did, metadata, 3600);
    cache.invalidate(&did);

    const entry = cache.get(&did);
    try std.testing.expect(entry == null);
}

test "DID cache pruning" {
    var cache = DIDCache.init(std.testing.allocator);
    defer cache.deinit();

    const did1 = try DIDIdentifier.parse("did:mosaic:prune1");
    const did2 = try DIDIdentifier.parse("did:mosaic:prune2");

    try cache.store(&did1, "data1", 1);      // Short TTL
    try cache.store(&did2, "data2", 3600);   // Long TTL

    const initial_count = cache.count();
    try std.testing.expect(initial_count == 2);

    // Prune should run without error (actual expiration depends on timing)
    cache.prune();

    // Cache should still have entries (unless timing causes expiration)
    // In Phase 3, we'll add proper time mocking for this test
}
