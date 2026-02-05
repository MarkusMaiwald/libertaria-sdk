// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Libertaria Contributors
// This file is part of the Libertaria Core, licensed under
// The Libertaria Commonwealth License v1.0.


const std = @import("std");

// LWF types are available directly via the lwf module import
// (mod.zig IS the lwf module root in build.zig)
pub const LWFHeader = @import("lwf.zig").LWFHeader;
pub const LWFFrame = @import("lwf.zig").LWFFrame;
pub const LWFFlags = @import("lwf.zig").LWFFlags;
pub const FrameClass = @import("lwf.zig").FrameClass;

// Re-export Time primitives
pub const time = @import("time.zig");

// Note: UTCP is available as a separate module, not re-exported here
// to avoid circular module dependencies (utcp needs lwf as module import)

// Note: opq/service/utcp tested separately via their own modules
// (avoiding circular module dependencies)

// Re-export Transport Skins (DPI evasion)
pub const skins = @import("transport_skins.zig");
pub const mimic_https = @import("mimic_https.zig");
pub const mimic_dns = @import("mimic_dns.zig");
pub const mimic_quic = @import("mimic_quic.zig");

// Re-export Noise Protocol Framework (Signal/WireGuard crypto)
pub const noise = @import("noise.zig");

// Re-export Polymorphic Noise Generator (traffic shaping)
pub const png = @import("png.zig");

// Re-export DHT (Distributed Hash Table)
pub const dht = @import("dht.zig");

// Re-export Gateway (NAT traversal)
pub const gateway = @import("gateway.zig");

// Re-export Relay (Onion routing)
pub const relay = @import("relay.zig");

// Re-export Quarantine (Security lockdown)
pub const quarantine = @import("quarantine.zig");

test {
    // Test individual components that don't have circular import issues
    // Note: opq/service/utcp tested separately via their own modules
    _ = time;
    _ = skins;
    _ = mimic_https;
    _ = mimic_dns;
    _ = mimic_quic;
    _ = noise;
    _ = png;
    _ = dht;
    _ = gateway;
    _ = relay;
    _ = quarantine;
}
