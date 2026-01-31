# Membrane Agent

**L2 Trust-Based Policy Enforcement Daemon for Libertaria**

The Membrane Agent is a Rust-based daemon that acts as the immune system for a Libertaria node. It sits between the L0 Transport Layer (UTCP) and the Application Layer, enforcing policies based on the L1 QVL Trust Graph.

## 🏗️ Architecture

- **L0 Hooks**: Listens for packet events (receipt, connection).
- **QVL FFI**: Queries the Zig-based QVL via C ABI for trust scores and betrayal detection.
- **Policy Enforcer**: Decides to `Accept`, `Deprioritize`, or `Drop` packets based on sender trust.
- **Anomaly Alerts**: Emits P0/P1 alerts when Betrayal (negative cycles) is detected.

## 🚀 Running

### Prerequisites
- Zig 0.15.2+ (to build `liblibertaria_sdk`)
- Rust 1.80+

### Build

First, build the Zig SDK static library:
```bash
cd libertaria-sdk
zig build
```

Then build the Rust daemon:
```bash
cd membrane-agent
cargo build --release
```

### Run
```bash
cargo run --release
```

## 🧪 Testing

```bash
# Run unit tests + FFI integration tests
cargo test
```

## 🔌 API Integration (Draft)

The agent exposes a control socket (TODO) and consumes L0 events via IPC (TODO).
Currently operates in STUB MODE for L0 integration.
