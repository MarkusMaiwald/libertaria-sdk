//! FFI bridge: Zig SHA3/SHAKE → C fips202.h interface
//!
//! Exports C-compatible functions so that Kyber's C code can call
//! Zig's SHA3/SHAKE implementations without needing a separate C library.

const std = @import("std");
const shake = @import("shake.zig");

// ============================================================================
// C-Compatible Exports (called from vendor/liboqs/*/fips202.c)
// ============================================================================

/// SHAKE-128: absorb input and squeeze output
/// C signature: void shake128(uint8_t *out, size_t outlen, const uint8_t *in, size_t inlen)
export fn shake128(out: [*]u8, outlen: usize, in: [*]const u8, inlen: usize) void {
    shake.shake128(out[0..outlen], in[0..inlen]);
}

/// SHAKE-256: absorb input and squeeze output
/// C signature: void shake256(uint8_t *out, size_t outlen, const uint8_t *in, size_t inlen)
export fn shake256(out: [*]u8, outlen: usize, in: [*]const u8, inlen: usize) void {
    shake.shake256(out[0..outlen], in[0..inlen]);
}

/// SHA3-256: hash input to 32-byte output
/// C signature: void sha3_256(uint8_t *out, const uint8_t *in, size_t inlen)
export fn sha3_256(out: [*]u8, in: [*]const u8, inlen: usize) void {
    var output: [32]u8 = undefined;
    shake.sha3_256(&output, in[0..inlen]);
    @memcpy(out[0..32], &output);
}

/// SHA3-512: hash input to 64-byte output
/// C signature: void sha3_512(uint8_t *out, const uint8_t *in, size_t inlen)
export fn sha3_512(out: [*]u8, in: [*]const u8, inlen: usize) void {
    var output: [64]u8 = undefined;
    shake.sha3_512(&output, in[0..inlen]);
    @memcpy(out[0..64], &output);
}

// ============================================================================
// Kyber-Specific Wrappers (for symmetric-shake.c compatibility)
// ============================================================================

/// kyber_shake128_absorb_once: Initialize SHAKE128 and absorb data, write output
/// Used by Kyber's symmetric-shake.c
export fn kyber_shake128_absorb_once(
    output: [*]u8,
    seed: [*]const u8,
    seedlen: usize,
    x: u8,
    y: u8,
) void {
    // Create temporary buffer: seed || x || y
    var buf: [34]u8 = undefined;
    if (seedlen <= 32) {
        @memcpy(buf[0..seedlen], seed[0..seedlen]);
        buf[seedlen] = x;
        buf[seedlen + 1] = y;

        shake.shake128(output[0..32], buf[0 .. seedlen + 2]);
    } else {
        // Fallback for oversized seed (shouldn't happen in Kyber)
        @memcpy(buf[0..32], seed[0..32]);
        buf[32] = x;
        buf[33] = y;
        shake.shake128(output[0..32], &buf);
    }
}

/// kyber_shake256_prf: SHAKE256-based PRF for Kyber
/// Implements: SHAKE256(key || nonce, outlen)
export fn kyber_shake256_prf(
    out: [*]u8,
    outlen: usize,
    key: [*]const u8,
    keylen: usize,
    nonce: u8,
) void {
    // Buffer: key || nonce
    var buf: [33]u8 = undefined;
    if (keylen <= 32) {
        @memcpy(buf[0..keylen], key[0..keylen]);
        buf[keylen] = nonce;
        shake.shake256(out[0..outlen], buf[0 .. keylen + 1]);
    } else {
        // Fallback for oversized key
        @memcpy(buf[0..32], key[0..32]);
        buf[32] = nonce;
        shake.shake256(out[0..outlen], &buf);
    }
}

// ============================================================================
// Tests: Verify FFI bridge works correctly
// ============================================================================

test "FFI: shake128 bridge" {
    const input = "test";
    var output1: [32]u8 = undefined;

    // Call via FFI bridge
    shake128(@ptrCast(&output1), 32, @ptrCast(input.ptr), input.len);

    // Compare with direct call
    var output2: [32]u8 = undefined;
    shake.shake128(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "FFI: shake256 bridge" {
    const input = "test";
    var output1: [32]u8 = undefined;

    shake256(@ptrCast(&output1), 32, @ptrCast(input.ptr), input.len);

    var output2: [32]u8 = undefined;
    shake.shake256(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "FFI: sha3_256 bridge" {
    const input = "test";
    var output1: [32]u8 = undefined;

    sha3_256(@ptrCast(&output1), @ptrCast(input.ptr), input.len);

    var output2: [32]u8 = undefined;
    shake.sha3_256(&output2, input);

    try std.testing.expectEqualSlices(u8, &output1, &output2);
}

test "FFI: kyber_shake128_absorb_once" {
    const seed = "seed_data_1234567890123456789012";
    const x = 0x01;
    const y = 0x02;
    var output: [32]u8 = undefined;

    kyber_shake128_absorb_once(
        @ptrCast(&output),
        @ptrCast(seed.ptr),
        seed.len,
        x,
        y,
    );

    // Verify output is not all zeros
    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }

    try std.testing.expect(!all_zero);
}

test "FFI: kyber_shake256_prf" {
    const key = "key_data";
    const nonce = 0x42;
    var output: [32]u8 = undefined;

    kyber_shake256_prf(
        @ptrCast(&output),
        32,
        @ptrCast(key.ptr),
        key.len,
        nonce,
    );

    // Verify output is not all zeros
    var all_zero = true;
    for (output) |byte| {
        if (byte != 0) {
            all_zero = false;
            break;
        }
    }

    try std.testing.expect(!all_zero);
}
