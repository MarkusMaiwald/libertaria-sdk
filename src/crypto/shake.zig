//! SHA3/SHAKE implementations using Zig stdlib
//!
//! Provides SHAKE-128/256 and SHA3-256/512 via Zig's standard library
//! with C-compatible FFI wrappers for Kyber's fips202 interface.

const std = @import("std");

// Re-export Zig's SHA3 types for convenience
pub const Shake128 = std.crypto.hash.sha3.Shake128;
pub const Shake256 = std.crypto.hash.sha3.Shake256;
pub const Sha3_256 = std.crypto.hash.sha3.Sha3_256;
pub const Sha3_512 = std.crypto.hash.sha3.Sha3_512;

/// SHAKE-128 XOF (eXtendable Output Function)
/// Absorbs input and produces arbitrary-length output
pub fn shake128(output: []u8, input: []const u8) void {
    var h = Shake128.init(.{});
    h.update(input);
    h.squeeze(output);
}

/// SHAKE-256 XOF
pub fn shake256(output: []u8, input: []const u8) void {
    var h = Shake256.init(.{});
    h.update(input);
    h.squeeze(output);
}

/// SHA3-256 (fixed output: 32 bytes)
pub fn sha3_256(output: *[32]u8, input: []const u8) void {
    Sha3_256.hash(input, output, .{});
}

/// SHA3-512 (fixed output: 64 bytes)
pub fn sha3_512(output: *[64]u8, input: []const u8) void {
    Sha3_512.hash(input, output, .{});
}

/// Streaming SHAKE-128 context for Kyber's absorb-squeeze pattern
pub const Shake128Context = struct {
    h: Shake128,
    finalized: bool,

    pub fn init() Shake128Context {
        return .{
            .h = Shake128.init(.{}),
            .finalized = false,
        };
    }

    pub fn absorb(self: *Shake128Context, input: []const u8) void {
        if (!self.finalized) {
            self.h.update(input);
        }
    }

    pub fn finalize(self: *Shake128Context) void {
        self.finalized = true;
    }

    pub fn squeeze(self: *Shake128Context, output: []u8) void {
        if (!self.finalized) {
            self.finalize();
        }
        self.h.squeeze(output);
    }

    pub fn reset(self: *Shake128Context) void {
        self.h = Shake128.init(.{});
        self.finalized = false;
    }
};

/// Streaming SHAKE-256 context
pub const Shake256Context = struct {
    h: Shake256,
    finalized: bool,

    pub fn init() Shake256Context {
        return .{
            .h = Shake256.init(.{}),
            .finalized = false,
        };
    }

    pub fn absorb(self: *Shake256Context, input: []const u8) void {
        if (!self.finalized) {
            self.h.update(input);
        }
    }

    pub fn finalize(self: *Shake256Context) void {
        self.finalized = true;
    }

    pub fn squeeze(self: *Shake256Context, output: []u8) void {
        if (!self.finalized) {
            self.finalize();
        }
        self.h.squeeze(output);
    }

    pub fn reset(self: *Shake256Context) void {
        self.h = Shake256.init(.{});
        self.finalized = false;
    }
};

// ============================================================================
// Tests: Determinism and Basic Properties
// ============================================================================

test "SHAKE128: deterministic output" {
    const input = "test_data";
    var output1: [32]u8 = undefined;
    var output2: [32]u8 = undefined;

    shake128(&output1, input);
    shake128(&output2, input);

    // Same input → same output
    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHAKE128: non-zero output" {
    const input = "";
    var output: [32]u8 = undefined;

    shake128(&output, input);

    // Output should not be all zeros
    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "SHAKE256: deterministic output" {
    const input = "test_data";
    var output1: [32]u8 = undefined;
    var output2: [32]u8 = undefined;

    shake256(&output1, input);
    shake256(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHAKE256: non-zero output" {
    const input = "";
    var output: [32]u8 = undefined;

    shake256(&output, input);

    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "SHA3-256: deterministic output" {
    const input = "test_data";
    var output1: [32]u8 = undefined;
    var output2: [32]u8 = undefined;

    sha3_256(&output1, input);
    sha3_256(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHA3-256: non-zero output" {
    const input = "test";
    var output: [32]u8 = undefined;

    sha3_256(&output, input);

    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "SHA3-512: deterministic output" {
    const input = "test_data";
    var output1: [64]u8 = undefined;
    var output2: [64]u8 = undefined;

    sha3_512(&output1, input);
    sha3_512(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHA3-512: non-zero output" {
    const input = "test";
    var output: [64]u8 = undefined;

    sha3_512(&output, input);

    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "SHAKE128 streaming context" {
    var ctx = Shake128Context.init();

    // Absorb in parts
    ctx.absorb("hello");
    ctx.absorb(" ");
    ctx.absorb("world");
    ctx.finalize();

    var output1: [32]u8 = undefined;
    ctx.squeeze(&output1);

    // Compare with non-streaming
    var output2: [32]u8 = undefined;
    shake128(&output2, "hello world");

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHAKE256 streaming context" {
    var ctx = Shake256Context.init();

    ctx.absorb("test");
    ctx.absorb("data");
    ctx.finalize();

    var output1: [32]u8 = undefined;
    ctx.squeeze(&output1);

    var output2: [32]u8 = undefined;
    shake256(&output2, "testdata");

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "SHAKE128 variable length output" {
    const input = "test";

    var short: [16]u8 = undefined;
    shake128(&short, input);

    var long: [64]u8 = undefined;
    shake128(&long, input);

    // First 16 bytes of long output should match short output
    try std.testing.expectEqualSlices(u8, &short, long[0..16]);
}
