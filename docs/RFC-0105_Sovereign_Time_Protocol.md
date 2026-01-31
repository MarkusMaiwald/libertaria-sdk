# RFC-0105: Sovereign Time Protocol (STP)

## Overview
The Sovereign Time Protocol (STP) defines the temporal dimension of the Libertaria network. It rejects the limitations of relative system ticks in favor of a sovereign, absolute, and ultra-high-precision time coordinate system.

## 1. Sovereign Timestamp
Time is represented as **Attoseconds (10^-18 s)** since an absolute **Anchor Epoch**.
- **Type:** `u128` (128-bit unsigned integer).
- **Range:** ~10^21 years (exceeds Heat Death of the Universe).
- **Precision:** Sub-atomic timescale precision.

### 1.1 Anchor Epochs
To allow interoperability with legacy systems ("The Old World") and objective reality, STP supports multiple anchors:
- `Unix1970`: 1970-01-01 00:00:00 UTC (Legacy compatibility).
- `BitcoinGenesis`: 2009-01-03 18:15:05 UTC (The Immutable Anchor).
- `SystemBoot`: Monotonic relative time (Local/Ephemeral).
- `GPSEpoch`: 1980-01-06 (Precision GNSS).

## 2. Temporal Epochs (Discretized Time)
To facilitate synchronization, key rotation, and periodic maintainence without central coordination, time is divided into **Epochs**.

### 2.1 Definition
An **Epoch** is a fixed duration slice of the timeline.
- **Duration:** 1 Hour (`3600` seconds).
- **Boundary:** Aligned to the Anchor. (e.g., Top of the hour).

### 2.2 Usage
Epochs serve as the heartbeat of the Sovereign Node:
1.  **Key Rotation:** Ephemeral encryption keys expire at Epoch boundaries.
2.  **Session Renewal:** Long-lived sessions must re-handshake every $N$ epochs.
3.  **Cron Scheduling:** Nodes use `Epoch.timeRemaining()` to sleep efficiently until the next synchronization window.
4.  **Rate Limiting:** Resource quotas are reset per Epoch.

### 2.3 Implementation
```zig
const time = @import("l0-transport/time.zig");
const now = time.SovereignTimestamp.now();
const epoch = time.Epoch.fromTimestamp(now);

// Check if we need to rotate keys
if (epoch.index > last_rotation_epoch) {
    rotateKeys();
}

// Sleep until next epoch
const sleep_duration = epoch.timeRemaining(now);
```

## 3. Wire Format
- **SovereignTimestamp:** 17 bytes (`u128` + `u8` Anchor).
- **CompactTimestamp:** 9 bytes (`u64` nanoseconds + `u8` Anchor) - used for Kenya devices (IoT).

