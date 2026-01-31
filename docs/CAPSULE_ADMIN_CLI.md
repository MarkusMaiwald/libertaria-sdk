# Capsule Admin CLI Reference

**Date:** 2026-01-31
**Version:** 0.1.0

## Overview

The Capsule Admin CLI provides direct control over the `capsule-daemon` via a Unix Domain Socket. It enables node operators to manage peers, inspect internal state, and enforce emergency network security measures.

## Commands

### 🛡️ Emergency Security

| Command | Arguments | Description |
|:---|:---|:---|
| `lockdown` | None | **EMERGENCY STOP.** Immediately drops ALL network traffic. |
| `unlock` | None | Disengages lockdown and resumes normal operation. |
| `airlock` | `<open/restricted/closed>` | Sets the Airlock mode (see below). |
| `slash` | `<did> <reason> <severity>` | Manually slashes a peer (Quarantine/Ban). |
| `ban` | `<did> [reason]` | Bans a peer manually (adds to blocklist). |
| `unban` | `<did>` | Removes a peer from the ban list. |

#### Airlock Modes
- **Open:** Normal operation. All valid traffic accepted.
- **Restricted:** Only traffic from explicitly trusted DIDs is accepted.
- **Closed:** Same as `lockdown`. Drops all traffic.

### 🔍 Diagnostics & Inspection

| Command | Arguments | Description |
|:---|:---|:---|
| `identity` | None | Shows local node DID, public key, and DHT ID. |
| `status` | None | Shows general node health and uptime. |
| `peers` | None | Lists currently connected TCP peers. |
| `sessions` | None | Lists active cryptographic sessions (Handshake/Active). |
| `dht` | None | Shows DHT routing table statistics and node ID. |
| `qvl-query` | `[did]` | Queries Trust/Risk metrics for a DID (or global). |
| `slash-log` | `[limit]` | Views recent slashing events. |

### 🤝 Trust Management

| Command | Arguments | Description |
|:---|:---|:---|
| `trust` | `<did> <score>` | Manually overrides trust score (0.0 - 1.0). |

## Usage Examples

### 1. Emergency Lockdown
```bash
# Stop all traffic immediately
capsule lockdown

# Check status (should show "is_locked: true")
capsule status

# Resume operations
capsule unlock
```

### 2. Investigating a Malicious Peer
```bash
# Check trust metrics
capsule qvl-query <suspect_did>

# View recent bad behavior
capsule slash-log 10

# Ban the peer
capsule ban <suspect_did> "Suspicious traffic patterns"
```

### 3. Network Diagnostics
```bash
# Am I connected to the DHT?
capsule dht

# Who am I talking to?
capsule sessions
```

## Architecture Notes

- **Control Socket:** Commands are sent via JSON over a Unix Domain Socket (`/tmp/capsule.sock`).
- **Atomic Locking:** exist at the L0 Transport layer (`L0Service`). Lockdown is an atomic boolean check in the hot path, ensuring zero-latency blocking.
- **Identity:** The `identity` command utilizes the local `SoulKey` without exposing private keys, using only the derived public key and DID.
