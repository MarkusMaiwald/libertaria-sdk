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
Wire protocol implementation for fixed-size headers and variable payloads. Supports CRC32-C and Ed25519.

### Time - `time.zig`
**RFC:** RFC-0105  
Nanosecond precision transport-layer time primitives.

### UTCP (Unreliable Transport Protocol) - `utcp/socket.zig`
**RFC:** RFC-0010  
Fast-path UDP wrapper for LWF frames. Features rapid entropy validation (DoS defense) before deep parsing.

### OPQ (Offline Packet Queue) - `opq/`
**RFC:** RFC-0020  
High-resilience store-and-forward mechanism using a **Segmented WAL** (Write-Ahead Log) for 72-96 hour packet retention.

### L0 Service - `service.zig`
The integrated engine that orchestrates `Network -> UTCP -> OPQ -> Ingestion`. Handles automated maintenance and persona-based policies.

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
