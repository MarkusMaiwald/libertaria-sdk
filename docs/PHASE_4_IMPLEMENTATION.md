# Phase 4: L0 Transport & Queueing (UTCP + OPQ)

**Status:** ⏳ IN PREPARATION
**Target:** L0 Transport Layer (`l0-transport/`)
**RFCs:** RFC-0004 (UTCP), RFC-0005 (OPQ)

## Overview

Phase 4 moves the project from static "Wire Frames" (LWF) to an active **Transport Layer**. It introduces the ability to send/receive packets over the network and manage offline persistence for asynchronous communication.

## Scope

### 1. UTCP: Unreliable Transport Protocol (UDP)
- **Component:** `l0-transport/utcp.zig`
- **Function:** Fast-path UDP wrapper for LWF frames.
- **Key Features:**
    - Non-blocking UDP socket abstraction.
    - Zero-copy frame ingestion (points directly into receive buffer).
    - Rapid entropy validation (L1 check) before full frame parsing.
    - Path MTU discovery (basic) for LWF FrameClass selection.

### 2. OPQ: Offline Packet Queue
- **Component:** `l0-transport/opq.zig`
- **Function:** High-resilience store-and-forward mechanism.
- **Key Features:**
    - **Node Personas:**
        - *Client:* Outbox only (Retention: <1hr, Buffer: <5MB).
        - *Relay:* Store-and-Forward (Retention: 72-96hr, Buffer: Quota-driven).
    - **Segmented WAL Storage:** Persistent storage using 4MB segments for corruption isolation and atomic rotation.
    - **Queue Manifests:** Merkle-committed summaries of currently stored frames for selective fetch.
    - **Quota Management:** Hard disk-space limits and priority-based eviction (Least Trusted First/Expired First).
    - **Automatic Pruning:** TTL-driven segment removal.

### 3. Frame Pipeline Integration
- **Component:** `l0_transport.zig` (Index)
- **Function:** Orchestrating the flow: `UDP -> Ingestion -> OPQ -> Application`.

## Architecture

```
[ PEER ] <--- UDP ---> [ UTCP Socket ]
                            |
                     [ Frame Validator ] (Signature/Entropy/Timestamp)
                            |
                     [ OPQ (Persistent) ] <--- [ Storage ]
                            |
                     [ L1 State Machine ]
```

## Readiness Checklist
- [x] Phase 3 PQXDH Handshake complete.
- [x] LWF Framing stable and tested.
- [ ] UDP Socket abstraction prototyped.
- [ ] Persistent storage engine selected (Simple WAL or Direct Filesystem).

## Success Metrics
- **Performance:** <5ms from UDP packet arrival to OPQ persistence.
- **Resilience:** Lossless storage during 72-hour offline periods.
- **Security:** Zero frame processing for invalid entropy stamps (DoS protection).
