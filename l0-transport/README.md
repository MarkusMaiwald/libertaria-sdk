# L0 Transport Layer

**Layer:** L0 (Transport)  
**Purpose:** Wire protocols, frame encoding, time primitives  
**RFCs:** RFC-0000 (LWF), RFC-0105 (Time L0 component)

---

## Overview

The L0 Transport layer provides low-level wire protocol implementations for the Libertaria network. It handles packet framing, serialization, and transport-layer timestamps.

## Components

### LWF (Libertaria Wire Frame) - `lwf.zig`
**RFC:** RFC-0000  
**Size:** 72-byte header + payload + 36-byte trailer

Wire protocol implementation with:
- Fixed 72-byte header (24-byte DID hints, u64 nanosecond timestamp)
- Variable payload (1092-8892 bytes depending on frame class)
- 36-byte trailer (Ed25519 signature + CRC32 checksum)
- Frame classes (Constrained, Standard, Ethernet, Bulk, Jumbo)

**Key Types:**
- `LWFHeader` - 72-byte fixed header
- `LWFTrailer` - 36-byte signature + checksum
- `LWFFrame` - Complete frame wrapper
- `FrameClass` - Size negotiation enum

### Time - `time.zig`
**RFC:** RFC-0105 (L0 component)  
**Precision:** u64 nanoseconds (584-year range)

Transport-layer time primitives:
- `u64` nanosecond timestamps for drift detection
- Monotonic clock access
- Replay protection timestamps

**Note:** L1 uses full `SovereignTimestamp` (u128 attoseconds) for causal ordering.

---

## Usage

```zig
const l0 = @import("l0_transport.zig");

// Create LWF frame
var frame = try l0.lwf.LWFFrame.init(allocator, 1024);
defer frame.deinit(allocator);

// Set header fields
frame.header.service_type = 0x0700; // Vector message
frame.header.timestamp = l0.time.nowNanoseconds();

// Encode for transport
const encoded = try frame.encode(allocator);
defer allocator.free(encoded);
```

---

## Testing

Run L0 tests:
```bash
zig test l0-transport/lwf.zig
zig test l0-transport/time.zig
```

---

## Dependencies

- `std.mem` - Memory management
- `std.crypto` - CRC32, hashing
- `std.time` - System time access
