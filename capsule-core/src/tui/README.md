# Capsule TUI & Control Protocol Documentation

## Overview
The Capsule TUI Monitor (The "Luxury Deck") provides a real-time visualization of the node's internal state, network topology, and security events. It communicates with the Capsule daemon via a Unix Domain Socket using a custom JSON-based control protocol.

## Architecture

### 1. Control Protocol (`control.zig`)
A unified command/response schema shared between the daemon and any management client.
- **Commands**: `Status`, `Peers`, `Sessions`, `Topology`, `SlashLog`, `Shutdown`, `Lockdown`, `Unlock`.
- **Responses**: Tagged unions containing specific telemetry data.

### 2. TUI Engine (`tui/`)
- **`app.zig`**: Orchestrates the Vaxis event loop. Spawns a dedicated background thread for non-blocking I/O with the daemon.
- **`client.zig`**: Implements the IPC client with mandatory deep-copying and explicit memory management to ensure a zero-leak footprint.
- **`view.zig`**: Renders the stateful UI components:
    - **Dashboard**: Core node stats (ID, Version, State, Uptime).
    - **Slash Log**: Real-time list of network security interventions.
    - **Trust Graph**: Circular topology visualization using f64 polar coordinates mapped to terminal cells.

## Memory Governance
In accordance with high-stakes SysOps standards:
- **Zero-Leak Polling**: Every data refresh explicitly frees the previously "duped" strings and slices.
- **Thread Safety**: `AppState` uses an internal Mutex to synchronize the rendering path with the background polling path.
- **Unmanaged Design**: Alignment with Zig 0.15.2 architecture by using explicit allocators for all dynamic structures.

## Usage
1. **Daemon**: Start the node using `./zig-out/bin/capsule start`.
2. **Monitor**: Connect the monitor using `./zig-out/bin/capsule monitor`.
3. **Navigation**: 
    - `Tab`: Cycle between Dashboard, Slash Log, and Trust Graph.
    - `Ctrl+C` or `Q`: Exit monitor.

## Current Technical Debt
- [ ] Implement `uptime_seconds` tracking in `node.zig`.
- [ ] Implement `dht_node_id` extraction for IdentityInfo.
- [ ] Add interactive node inspection in the Trust Graph view.
