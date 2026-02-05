# UTCP: Unreliable Transport Protocol

**Layer:** L0 (Transport)
**RFC:** RFC-0004

## Purpose
UTCP provides the UDP-based transmission layer for Libertaria. It focuses on:
- High-throughput ingestion of LWF frames.
- Low-latency entropy validation.
- Connectionless UDP socket management.

## Components
- `socket.zig`: Bound UDP socket abstraction.
- `protocol.zig`: (Pending) MTU discovery and class selection.
