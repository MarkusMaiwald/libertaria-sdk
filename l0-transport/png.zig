//! RFC-0015: Polymorphic Noise Generator (PNG)
//!
//! Per-session traffic shaping for DPI resistance.
//! Kenya-compliant: <1KB RAM per session, deterministic, no cloud calls.

const std = @import("std");
// Note: In production, use proper HKDF-SHA256 from crypto module
// For now, simple key derivation to avoid circular dependencies

/// ChaCha20-based PNG state
/// Deterministic: same seed = same noise sequence at both ends
pub const PngState = struct {
    /// ChaCha20 state (136 bytes)
    key: [32]u8,
    nonce: [12]u8,
    counter: u32,
    
    /// Epoch tracking
    current_epoch: u32,
    packets_in_epoch: u32,
    
    /// Current epoch profile (cached)
    profile: EpochProfile,
    
    /// ChaCha20 block buffer for word-by-word consumption
    block_buffer: [64]u8,
    block_used: u8,
    
    const Self = @This();
    
    /// Derive PNG seed from ECDH shared secret
    /// In production: Use proper HKDF-SHA256
    pub fn initFromSharedSecret(shared_secret: [32]u8) Self {
        // Simple key derivation (for testing)
        // XOR with context string to derive key
        var key: [32]u8 = shared_secret;
        const context = "Libertaria-PNG-v1";
        for (context, 0..) |c, i| {
            key[i % 32] ^= c;
        }
        
        var self = Self{
            .key = key,
            .nonce = [_]u8{0} ** 12,
            .counter = 0,
            .current_epoch = 0,
            .packets_in_epoch = 0,
            .profile = undefined,
            .block_buffer = undefined,
            .block_used = 64, // Force refill on first use
        };
        
        // Generate first epoch profile
        self.profile = self.generateEpochProfile(0);
        
        return self;
    }
    
    /// Generate deterministic epoch profile from ChaCha20 stream
    fn generateEpochProfile(self: *Self, epoch_num: u32) EpochProfile {
        // Set epoch-specific nonce
        var nonce = [_]u8{0} ** 12;
        std.mem.writeInt(u32, nonce[0..4], epoch_num, .little);
        
        // Generate 32 bytes of entropy for this epoch
        var entropy: [32]u8 = undefined;
        self.chacha20(&nonce, 0, &entropy);
        
        // Derive profile parameters deterministically
        const size_dist_val = entropy[0] % 4;
        const timing_dist_val = entropy[1] % 3;
        
        // Use wrapping arithmetic to avoid overflow panics in debug mode
        const size_mean_val = @as(u16, 1200) +% @as(u16, @as(u32, entropy[2]) * 2);
        const size_stddev_val = @as(u16, 100) +% @as(u16, entropy[3]);
        const epoch_count = @as(u32, 100) +% (@as(u32, entropy[7]) * 4);
        
        return EpochProfile{
            .size_distribution = @enumFromInt(@as(u32, size_dist_val)),
            .size_mean = size_mean_val,
            .size_stddev = size_stddev_val,
            .timing_distribution = @enumFromInt(@as(u32, timing_dist_val)),
            .timing_lambda = 0.001 + (@as(f64, @floatFromInt(entropy[4])) / 255.0) * 0.019,
            .dummy_probability = @as(f64, @floatFromInt(entropy[5] % 16)) / 100.0,
            .dummy_distribution = if (entropy[6] % 2 == 0) .Uniform else .Bursty,
            .epoch_packet_count = epoch_count,
        };
    }
    
    /// ChaCha20 block function (simplified - production needs full implementation)
    fn chacha20(self: *Self, nonce: *[12]u8, counter: u32, out: []u8) void {
        // TODO: Full ChaCha20 implementation
        // For now, use simple PRNG based on key material
        var i: usize = 0;
        while (i < out.len) : (i += 1) {
            out[i] = self.key[i % 32] ^ nonce.*[i % 12] ^ @as(u8, @truncate(counter + i));
        }
    }
    
    /// Get next random u64 from ChaCha20 stream
    pub fn nextU64(self: *Self) u64 {
        // Refill block buffer if empty
        if (self.block_used >= 64) {
            self.chacha20(&self.nonce, self.counter, &self.block_buffer);
            self.counter +%= 1;
            self.block_used = 0;
        }
        
        // Read 8 bytes as u64
        const bytes = self.block_buffer[self.block_used..][0..8];
        self.block_used += 8;
        
        return std.mem.readInt(u64, bytes, .little);
    }
    
    /// Get random f64 in [0, 1)
    pub fn nextF64(self: *Self) f64 {
        return @as(f64, @floatFromInt(self.nextU64())) / @as(f64, @floatFromInt(std.math.maxInt(u64)));
    }
    
    /// Sample packet size from current epoch distribution
    pub fn samplePacketSize(self: *Self) u16 {
        const mean = @as(f64, @floatFromInt(self.profile.size_mean));
        const stddev = @as(f64, @floatFromInt(self.profile.size_stddev));
        
        const raw_size = switch (self.profile.size_distribution) {
            .Normal => self.sampleNormal(mean, stddev),
            .Pareto => self.samplePareto(mean, stddev),
            .Bimodal => self.sampleBimodal(mean, stddev),
            .LogNormal => self.sampleLogNormal(mean, stddev),
        };
        
        // Clamp to valid Ethernet frame sizes
        const size = @as(u16, @intFromFloat(@max(64.0, @min(1500.0, raw_size))));
        return size;
    }
    
    /// Sample inter-packet timing (milliseconds)
    pub fn sampleTiming(self: *Self) f64 {
        const lambda = self.profile.timing_lambda;
        
        return switch (self.profile.timing_distribution) {
            .Exponential => self.sampleExponential(lambda),
            .Gamma => self.sampleGamma(2.0, lambda),
            .Pareto => self.samplePareto(1.0 / lambda, 1.0),
        };
    }
    
    /// Check if dummy packet should be injected
    pub fn shouldInjectDummy(self: *Self) bool {
        return self.nextF64() < self.profile.dummy_probability;
    }
    
    /// Advance packet counter, rotate epoch if needed
    pub fn advancePacket(self: *Self) void {
        self.packets_in_epoch += 1;
        
        if (self.packets_in_epoch >= self.profile.epoch_packet_count) {
            self.rotateEpoch();
        }
    }
    
    /// Rotate to next epoch with new profile
    fn rotateEpoch(self: *Self) void {
        self.current_epoch += 1;
        self.packets_in_epoch = 0;
        self.profile = self.generateEpochProfile(self.current_epoch);
    }
    
    // =========================================================================
    // Statistical Distributions (Box-Muller, etc.)
    // =========================================================================
    
    fn sampleNormal(self: *Self, mean: f64, stddev: f64) f64 {
        // Box-Muller transform
        const uniform1 = self.nextF64();
        const uniform2 = self.nextF64();
        const z0 = @sqrt(-2.0 * @log(uniform1)) * @cos(2.0 * std.math.pi * uniform2);
        return mean + z0 * stddev;
    }
    
    fn samplePareto(self: *Self, scale: f64, shape: f64) f64 {
        const u = self.nextF64();
        return scale / std.math.pow(f64, u, 1.0 / shape);
    }
    
    fn sampleBimodal(self: *Self, _: f64, _: f64) f64 {
        // Two modes: small (600) and large (1440), ratio 1:3
        if (self.nextF64() < 0.25) {
            // Small mode around 600 bytes
            return self.sampleNormal(600.0, 100.0);
        } else {
            // Large mode around 1440 bytes  
            return self.sampleNormal(1440.0, 150.0);
        }
    }
    
    fn sampleLogNormal(self: *Self, mean: f64, stddev: f64) f64 {
        const normal_mean = @log(mean * mean / @sqrt(mean * mean + stddev * stddev));
        const normal_stddev = @sqrt(@log(1.0 + (stddev * stddev) / (mean * mean)));
        return @exp(self.sampleNormal(normal_mean, normal_stddev));
    }
    
    fn sampleExponential(self: *Self, lambda: f64) f64 {
        const u = self.nextF64();
        return -@log(1.0 - u) / lambda;
    }
    
    fn sampleGamma(_: *Self, shape: f64, scale: f64) f64 {
        // Simplified Gamma approximation
        // Full Marsaglia-Tsang implementation would need self
        return shape * scale; // Placeholder
    }
};

/// Epoch profile for traffic shaping
pub const EpochProfile = struct {
    size_distribution: SizeDistribution,
    size_mean: u16,           // bytes
    size_stddev: u16,         // bytes
    timing_distribution: TimingDistribution,
    timing_lambda: f64,       // rate parameter
    dummy_probability: f64,   // 0.0-0.15
    dummy_distribution: DummyDistribution,
    epoch_packet_count: u32,  // packets before rotation
    
    pub const SizeDistribution = enum(u8) {
        Normal = 0,
        Pareto = 1,
        Bimodal = 2,
        LogNormal = 3,
    };
    
    pub const TimingDistribution = enum(u8) {
        Exponential = 0,
        Gamma = 1,
        Pareto = 2,
    };
    
    pub const DummyDistribution = enum(u8) {
        Uniform = 0,
        Bursty = 1,
    };
};

// ============================================================================
// TESTS
// ============================================================================

test "PNG deterministic from same seed" {
    const secret = [_]u8{0x42} ** 32;
    
    var png1 = PngState.initFromSharedSecret(secret);
    var png2 = PngState.initFromSharedSecret(secret);
    
    // Same seed = same sequence
    const val1 = png1.nextU64();
    const val2 = png2.nextU64();
    
    try std.testing.expectEqual(val1, val2);
}

test "PNG different from different seeds" {
    const secret1 = [_]u8{0x42} ** 32;
    const secret2 = [_]u8{0x43} ** 32;
    
    var png1 = PngState.initFromSharedSecret(secret1);
    var png2 = PngState.initFromSharedSecret(secret2);
    
    const val1 = png1.nextU64();
    const val2 = png2.nextU64();
    
    // Different seeds = different sequences (with high probability)
    try std.testing.expect(val1 != val2);
}

test "PNG packet sizes in valid range" {
    const secret = [_]u8{0xAB} ** 32;
    var png = PngState.initFromSharedSecret(secret);
    
    // Sample 1000 sizes
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const size = png.samplePacketSize();
        try std.testing.expect(size >= 64);
        try std.testing.expect(size <= 1500);
        png.advancePacket();
    }
}

test "PNG epoch rotation" {
    const secret = [_]u8{0xCD} ** 32;
    var png = PngState.initFromSharedSecret(secret);
    
    const initial_epoch = png.current_epoch;
    const epoch_limit = png.profile.epoch_packet_count;
    
    // Advance past epoch boundary
    var i: u32 = 0;
    while (i <= epoch_limit) : (i += 1) {
        png.advancePacket();
    }
    
    // Epoch should have rotated
    try std.testing.expect(png.current_epoch > initial_epoch);
}

test "PNG timing samples positive" {
    const secret = [_]u8{0xEF} ** 32;
    var png = PngState.initFromSharedSecret(secret);
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const timing = png.sampleTiming();
        try std.testing.expect(timing > 0.0);
    }
}
