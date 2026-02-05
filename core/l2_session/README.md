# L2 Session Manager

Sovereign peer-to-peer session management for Libertaria.

## Overview

The L2 Session Manager establishes and maintains cryptographically verified sessions between Libertaria nodes. It provides:

- **Post-quantum security** (X25519Kyber768 hybrid)
- **Resilient state machines** (graceful degradation, automatic recovery)
- **Seamless key rotation** (no message loss during rotation)
- **Multi-transport support** (QUIC primary, μTCP fallback)

## Why No WebSockets

This module explicitly excludes WebSockets (see ADR-001). We use:

| Transport | Use Case | Advantages |
|-----------|----------|------------|
| **QUIC** | Primary transport | 0-RTT, built-in TLS, multiplexing |
| **μTCP** | Fallback, legacy | Micro-optimized, minimal overhead |
| **UDP** | Discovery, broadcast | Stateless, fast probing |

WebSockets add HTTP overhead, proxy complexity, and fragility. Libertaria is built for the 2030s, not the 2010s.

## Quick Start

```janus
// Establish session
let session = try l2_session.establish(
    peer_did: "did:morpheus:abc123",
    config: .{ ttl: 24h, heartbeat: 30s },
    ctx: ctx
);

// Use session
try session.send(message);
let response = try session.receive(timeout: 5s);
```

## State Machine

```
idle → handshake_initiated → established → degraded → suspended
         ↓                           ↓          ↓
       failed                    rotating → established
```

See SPEC.md for full details.

## Module Structure

| File | Purpose |
|------|---------|
| `session.zig` | Core Session struct and API |
| `state.zig` | State machine definitions and transitions |
| `handshake.zig` | PQxdh handshake implementation |
| `heartbeat.zig` | Keepalive and TTL management |
| `rotation.zig` | Key rotation without interruption |
| `transport.zig` | QUIC/μTCP abstraction layer |
| `error.zig` | Session-specific error types |
| `config.zig` | Configuration structures |

## Testing

Tests are colocated in `test_*.zig` files. Run with:

```bash
zig build test-l2-session
```

## Specification

Full specification in [SPEC.md](./SPEC.md).
