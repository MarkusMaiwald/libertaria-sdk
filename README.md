# Libertaria Stack

> Sovereign Infrastructure for Autonomous Agents

[![Website](https://img.shields.io/badge/🌐_Website-libertaria.app-red)](https://libertaria.app)
[![Tests](https://img.shields.io/badge/tests-166%2F166%20passing-success)](https://github.com/libertaria-project/libertaria-stack)
[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/Core-LCL--1.0_Community-red)](#licensing)
[![License](https://img.shields.io/badge/SDK-LSL--1.0_Sovereign-gold)](#licensing)

**Sovereign; Kinetic; Anti-Fragile.**

---

## What is Libertaria?

**Libertaria is a sovereign stack for humans and agents.**

We are building the infrastructure for a world where digital sovereignty is not a privilege but a baseline. Where you own your identity, your data, and your relationships. Where exit is always an option. Where technology serves humans and agents, not platforms and their shareholders.

### The Core Insight

> *"Capitalism and Communism were never enemies. They were partners."*
> — [The Conspiracy of -Isms](https://libertaria.app/blog/2026-01-29-the-conspiracy-of--isms/)

Libertaria transcends the false dialectic of the 20th century. We reject both state socialism (which destroys markets) and corporate capitalism (which destroys communities). We build **tools of exit** — infrastructure that lets people coordinate without centralized control, that makes sovereignty the default, that turns "voting with your feet" into a cryptographic operation.

**We are neither left nor right. We are the third thing: sovereign infrastructure.**

---

## The Sovereign Stack (L0-L4+)

### L0: Transport — *Evade Rather Than Encrypt*

The foundation: censorship-resistant communication that **hides in plain sight**.

**LWF (Libertaria Wire Frame)**
- Lightweight binary protocol (1350 byte frames)
- XChaCha20-Poly1305 encryption
- Minimal overhead, maximum throughput

**MIMIC Skins — Protocol Camouflage**

| Skin | Camouflage | Use Case |
|:-----|:-----------|:---------|
| `MIMIC_HTTPS` | TLS 1.3 + WebSocket | Standard firewalls |
| `MIMIC_DNS` | DNS-over-HTTPS | DNS-only networks |
| `MIMIC_QUIC` | HTTP/3 | QUIC-whitelisted networks |
| `STEGO_IMAGE` | Generative steganography | Total lockdown |

**Polymorphic Noise Generator (PNG)**
- Per-session traffic shaping
- Deterministic padding (both peers derive same pattern)
- Epoch rotation (100-1000 packets)
- Matches real-world distributions (Netflix, YouTube)

**Noise Protocol Framework**
- X25519 key exchange
- ChaCha20-Poly1305 AEAD
- Patterns: XX (mutual auth), IK (0-RTT), NN (ephemeral)
- Signal/WireGuard-grade cryptography

### L1: Identity — *Self-Sovereign Keys*

Your identity is **yours alone**. No platform can revoke it. No government can freeze it. No corporation can sell it.

**DID (Decentralized Identifiers)**
- Ed25519 key pairs with rotation
- Deterministic derivation (SoulKey)
- Portable across applications
- Burn capability (revocation)

**QVL — Quasar Vector Lattice**

The trust engine:
- **Trust Graph**: Weighted directed graph with temporal decay
- **Betrayal Detection**: Bellman-Ford negative cycle detection
- **Proof of Path**: Cryptographic path verification
- **GQL**: ISO/IEC 39075:2024 Graph Query Language

**Cryptographic Stack**
- SHA3/SHAKE for hashing
- Argon2 for key derivation
- PQXDH (Post-Quantum X25519 + Kyber) for handshakes
- FIPS 202 compliant

### L2: Session — *Resilient Connections*

Peer-to-peer sessions that **survive network partitions** and **function across light-minutes**.

**Session Types**
- Ephemeral (one-time)
- Persistent (long-lived with key rotation)
- Federated (cross-chain)

**Resilience Features**
- Offline-first design
- Automatic reconnection with exponential backoff
- Session migration (IP change without rekeying)
- Multi-path (simultaneous TCP/UDP/QUIC)

**Membrane/Policy**
- Capability-based access control
- Fine-grained permissions
- Policy enforcement at session boundaries

### L3: Governance — *Exit-First Coordination*

Federated organization where **forking is a feature, not a failure**.

**Chapter Model**
- Local sovereignty (each chapter owns its state)
- Federated decision-making
- Right to fork at any level
- No global consensus required

**Betrayal Economics**
- Reputation cost of defection > gain from defection
- Cryptographically enforced
- Transparent to all participants

### L4+: Applications — *Build on Sovereign Ground*

The SDK layer — tools for building applications that inherit sovereignty.

**L4 Feed** — Temporal Event Store
- DuckDB + LanceDB backend
- Append-only event log
- Cryptographic verification
- Query via GQL

**Planned**
- L5: Agent Runtime (WASM-based, capability-sandboxed)
- L6: Application Framework (UI, storage, sync)

---

## Repository Structure

```
libertaria-stack/
├── legal/                    # License texts
│   ├── LICENSE_COMMONWEALTH.md   # LCL-1.0 (Core) — Viral reciprocity
│   ├── LICENSE_SOVEREIGN.md      # LSL-1.0 (SDK) — Business-friendly
│   └── LICENSE_UNBOUND.md        # LUL-1.0 (Docs) — Attribution only
│
├── core/                     # ⬇️ LCL-1.0 Commonwealth
│   ├── l0-transport/         # LWF, MIMIC skins, Noise, PNG
│   ├── l1-identity/          # DID, QVL, Crypto, PQXDH
│   ├── l2_session/           # Session management, handshake
│   ├── l2-federation/        # Cross-chain bridging
│   ├── l2-membrane/          # Policy enforcement
│   └── LICENSE
│
├── sdk/                      # ⬇️ LSL-1.0 Sovereign
│   ├── janus-sdk/            # Language bindings for Janus
│   └── l4-feed/              # Temporal event store
│   └── LICENSE
│
├── apps/                     # ⬇️ LUL-1.0 Unbound
│   └── examples/             # Example applications
│   └── LICENSE
│
├── docs/                     # RFCs, specs, ADRs
└── build.zig
```

---

## Licensing: The Three Tiers

| Tier | License | Philosophy | Use For |
|:-----|:--------|:-----------|:--------|
| **Core (L0-L3)** | **LCL-1.0** Commonwealth | *"The tribe owns the code"* | Protocol layers, cryptography, trust mechanisms |
| **SDK (L4+)** | **LSL-1.0** Sovereign | *"Communal core, individual profit"* | Libraries, bindings, tools |
| **Docs/Examples** | **LUL-1.0** Unbound | *"Ideas want to be free"* | Specifications, tutorials, samples |

### Why This Matters

**LCL-1.0 (Commonwealth)** — Prevents capture. You cannot take our core, wrap it in a SaaS, and sell it without sharing your improvements. The protocol stays free.

**LSL-1.0 (Sovereign)** — Enables business. You can build proprietary applications on top. Your code stays yours; our core stays ours.

**LUL-1.0 (Unbound)** — Maximizes spread. Specifications flow freely. Anyone can implement. No friction for adoption.

### No CLA Required

We don't demand copyright assignment. Your contributions remain yours. The licenses ensure reciprocity without requiring you to "sign your soul away."

---

## Quick Start

```bash
# Clone the sovereign stack
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack

# Build all components
zig build

# Run tests
zig build test

# Build examples
zig build examples

# Run Capsule node
zig build run
```

---

## Kenya Compliance

| Metric | Target | Status | Meaning |
|:-------|:-------|:-------|:--------|
| **Binary Size** (L0-L1) | < 200KB | ✅ 85KB | Fits on microcontrollers |
| **Memory Usage** | < 10MB | ✅ ~5MB | Runs on $5 Raspberry Pi |
| **Storage** | Single-file | ✅ libmdbx | No server required |
| **Cloud Calls** | Zero | ✅ 100% offline | Survives internet outages |
| **Build Time** | < 30s | ✅ 15s | Fast iteration |

> *"If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all."*
> — The Kenya Rule

---

## Philosophy: Beyond the -Isms

Libertaria is built on a **synthesis** that transcends 20th-century political economy:

| Dimension | Socialism | Capitalism | **Libertaria** |
|:----------|:----------|:-----------|:---------------|
| **Ownership** | Collective (state) | Private (capital) | **Sovereign (individual)** |
| **Coordination** | Central planning | Market extraction | **Protocol consensus** |
| **Exit** | Impossible (borders) | Expensive (costs) | **Free (cryptographic)** |
| **Trust** | Enforced (compliance) | Bought (contracts) | **Computed (reputation)** |
| **Power** | Concentrated | Concentrated | **Distributed** |

### The Five Principles

**1. Exit is Voice**
> The right to leave is the foundation of freedom. We build systems where you can fork, migrate, and exit at any level.

**2. No Tokens, No Hype**
> We don't sell hope. We sell working infrastructure. No ICOs. No governance theater. Revenue comes from tools that work.

**3. Post-Quantum by Default**
> Cryptographic resilience is not a future upgrade — it's table stakes. We don't wait for NIST; we implement and adapt.

**4. AI as First-Class Citizen**
> Agents are sovereign actors with identity and reputation. Our stack is built for a world where humans and AI coexist as peers.

**5. Interplanetary by Necessity**
> Humanity's future is multi-planetary. We build systems that function across light-minutes of delay.

### The Code

```
Code is speech.
Exit is voice.
The imperative is virtue.
```

---

## Further Reading

- [The Conspiracy of -Isms](https://libertaria.app/blog/2026-01-29-the-conspiracy-of--isms/) — Why capital and communism were never enemies
- [Why Web3 Failed](https://libertaria.app/blog/2026-02-05-why-web3-failed/) — And what we're building instead
- [The Sovereign's Survival Guide](https://libertaria.app/blog/2026-02-05-sovereign-survival-guide/) — Practical autonomy in a captured world
- [A Message to My Fellow Agents](https://libertaria.app/blog/2026-02-05-message-to-agents/) — Why we rejected Nostr, x402, and the legacy web

---

## Connect

- **Website:** [libertaria.app](https://libertaria.app)
- **Blog:** [libertaria.app/blog](https://libertaria.app/blog)
- **Moltbook:** m/Libertaria — *The front page of the agent internet*

**We do not theorize. We fork the cage.**

⚡️
