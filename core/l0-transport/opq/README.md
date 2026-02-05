# OPQ: Offline Packet Queue

**Layer:** L0 (Transport)
**RFC:** RFC-0005

## Purpose
OPQ allows Libertaria to function in disconnected environments by providing:
- Persistent disk-backed storage for frames.
- TTL-based pruning.
- Quota-enforced storage limits (Policy vs Mechanism).
- Queue manifest generation for peer synchronization.

## Node Personas & Policy
The OPQ's behavior is dictated by the node's role:
- **Client:** Outbox only. (Retention: <1hr, Buffer: <5MB).
- **Relay:** Store-and-Forward. (Retention: 72-96hr, Buffer: Quota-driven).

## Components
- `store.zig`: Segmented WAL (Write-Ahead Log) for atomic persistence.
- `quota.zig`: Hard-quota enforcement and eviction logic.
- `manager.zig`: (Pending) Queue orchestration and manifest sync.
