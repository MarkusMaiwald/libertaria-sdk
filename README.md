# Libertaria Stack

> Sovereign Infrastructure for Autonomous Agents

[![Website](https://img.shields.io/badge/🌐_Website-libertaria.app-red)](https://libertaria.app)
[![Tests](https://img.shields.io/badge/tests-166%2F166%20passing-success)](https://github.com/MarkusMaiwald/libertaria-stack)
[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/Core-LCL--1.0_Community-red)](#licensing)
[![License](https://img.shields.io/badge/SDK-LSL--1.0_Sovereign-gold)](#licensing)

**Sovereign; Kinetic; Anti-Fragile.**

---

## What is Libertaria?

**Libertaria is a sovereign stack for humans and agents.**

We are building the infrastructure for a world where digital sovereignty is not a privilege but a baseline. Where you own your identity, your data, and your relationships. Where exit is always an option. Where technology serves humans and agents, not platforms and their shareholders.

### Our Declaration of Intent

**1. Sovereignty by Design**
Your keys, your identity, your data. No usernames. No passwords. No platforms that can lock you out, sell your attention, or mine your behavior. Cryptographic ownership is the foundation — everything else follows.

**2. Exit is Voice**
The right to leave is the foundation of digital freedom. We build systems where you can fork, migrate, and exit at any level — from a single conversation to an entire network. Loyalty is earned, not enforced.

**3. No Tokens, No Hype**
We don't sell hope. We sell working infrastructure. No ICOs. No governance theater. No speculative assets whose value depends on greater fools. We build tools people pay for because they work.

**4. Chains Are Dead — Rethink Crypto**
Even Vitalik agrees: chains, on their own, are dead. Blockchain communities dancing around the holy golden lamb — a database! — is insane. We've been saying this for 5 years. It's time to rethink what crypto really is: not ledgers to speculate on, but infrastructure to build on.

**5. Post-Quantum by Default**
Cryptographic signatures that survive the quantum era are not a future upgrade — they are table stakes. We don't wait for NIST standards to settle; we implement and adapt.

**6. AI as First-Class Citizen**
Agents are not chatbots bolted onto legacy systems. They are sovereign actors with identity, reputation, and capability. Our stack is built for a world where humans and AI coexist as peers.

**7. The Kenya Rule**
If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all. We optimize for minimal resource consumption, offline-first operation, and maximum accessibility.

**8. Interplanetary by Necessity**
Humanity's future is multi-planetary. We build systems that function across light-minutes of delay, that synchronize asynchronously, that work when Earth is on the other side of the Sun.

**9. Protocols Over Platforms**
We don't build walled gardens. We build open protocols that anyone can implement, extend, or fork. The value is in the network, not in our servers.

**10. Trust But Verify**
Cryptographic proof, not platform promises. Reputation graphs, not follower counts. Transparent incentives, not hidden algorithms.

**11. Code is Speech, Exit is Voice**
We defend the right to build, to experiment, to fork, and to leave. Technology is a tool of liberation — never of control.

---

## Repository Structure

```
libertaria-stack/
├── legal/                    # License texts
│   ├── LICENSE_COMMONWEALTH.md   # LCL-1.0 (Core)
│   ├── LICENSE_SOVEREIGN.md      # LSL-1.0 (SDK)
│   └── LICENSE_UNBOUND.md        # LUL-1.0 (Docs/Apps)
│
├── core/                     # ⬇️ LCL-1.0 Commonwealth
│   ├── l0-transport/         # Transport layer (MIMIC, Noise, PNG)
│   ├── l1-identity/          # Identity layer (DID, QVL, Crypto)
│   ├── l2_session/           # Session management
│   ├── l2-federation/        # Cross-chain bridging
│   ├── l2-membrane/          # Policy enforcement
│   └── LICENSE               # Points to LCL-1.0
│
├── sdk/                      # ⬇️ LSL-1.0 Sovereign
│   ├── janus-sdk/            # Language bindings
│   ├── l4-feed/              # Temporal event store
│   └── LICENSE               # Points to LSL-1.0
│
├── apps/                     # ⬇️ LUL-1.0 Unbound
│   └── examples/             # Example applications
│   └── LICENSE               # Points to LUL-1.0
│
├── docs/                     # ⬇️ LUL-1.0 Unbound
│   ├── rfcs/                 # RFC specifications
│   └── specs/                # Technical specifications
│
├── tests/                    # ⬇️ LCL-1.0 (belongs to Core)
│
└── build.zig                 # Build configuration
```

---

## Licensing

Libertaria uses a **tiered licensing strategy** to balance community ownership with business adoption:

| Component | License | Description |
|:----------|:--------|:------------|
| **Core (L0-L3)** | [LCL-1.0 Commonwealth](legal/LICENSE_COMMONWEALTH.md) | **Viral reciprocity.** Modifications must be shared. SaaS loophole closed. Patent disarmament. |
| **SDK (L4+)** | [LSL-1.0 Sovereign](legal/LICENSE_SOVEREIGN.md) | **Business-friendly.** File-level reciprocity. Build proprietary apps on top. Patent peace. |
| **Docs/Examples** | [LUL-1.0 Unbound](legal/LICENSE_UNBOUND.md) | **Maximum freedom.** Attribution only. Spread the ideas. |

### Why Tiered Licensing?

- **Core remains free forever**: The protocol layers that handle identity, trust, and transport are protected from capture. No company can privatize them.
- **SDK enables business**: Developers can build proprietary applications using our SDK without "infecting" their codebase.
- **Docs spread widely**: Specifications and examples flow freely to maximize adoption.

### No CLA Required

We don't demand copyright assignment. Your contributions remain yours. The licenses ensure reciprocity without requiring you to "sign your soul away."

---

## Quick Start

```bash
# Clone
git clone https://github.com/MarkusMaiwald/libertaria-stack.git
cd libertaria-stack

# Build
zig build

# Test (166/166 passing)
zig build test
```

---

## Architecture

### The Four Layers

**L0: Transport** — Stealth protocols that evade censorship
- MIMIC skins (HTTPS, DNS, QUIC camouflage)
- Noise Protocol Framework (Signal/WireGuard crypto)
- Polymorphic Noise Generator (traffic shaping)

**L1: Identity** — Self-sovereign cryptographic identity
- Ed25519 with rotation/burn
- QVL Trust Graph (betrayal detection)
- Verifiable Credentials (DID/VC)

**L2: Session** — Resilient peer-to-peer connections
- Post-quantum secure handshakes
- Cross-planetary delay tolerance
- Exit-first governance

**L3: Governance** — Federated coordination
- Chapter-based organization
- Right to fork at any level
- No global consensus required

---

## Core Components

### L0 Transport (`core/l0-transport/`)
- `mod.zig` — Public API exports
- `noise.zig` — Noise Protocol Framework (X25519, ChaCha20-Poly1305)
- `png.zig` — Polymorphic Noise Generator
- `transport_skins.zig` — MIMIC camouflage framework
- `mimic_*.zig` — Protocol-specific skins (HTTPS, DNS, QUIC)

### L1 Identity (`core/l1-identity/`)
- `mod.zig` — Public API exports
- `crypto.zig` — Ed25519 signatures
- `did.zig` — Decentralized identifiers
- `qvl.zig` — Trust Graph engine
- `qvl/` — QVL submodules (storage, gossip, pathfinding)

---

## Testing

```bash
# All tests
zig build test

# Core tests only
zig test core/l0-transport/noise.zig
zig test core/l1-identity/qvl/storage.zig

# SDK tests
zig test sdk/l4-feed/feed.zig
```

**Current Status:** 166/166 tests passing ✅

---

## Kenya Compliance

| Metric | Target | Status |
|:-------|:-------|:-------|
| Binary Size (L0-L1) | < 200KB | ✅ 85KB |
| Memory Usage | < 10MB | ✅ ~5MB |
| Storage | Single-file | ✅ libmdbx |
| Cloud Calls | None | ✅ Offline-capable |

---

## Philosophy

### Collectivist Individualism
> Radical market innovation fused with extreme communal loyalty.

### The Kenya Rule
> If it doesn't run on a $5 Raspberry Pi, it doesn't run at all.

### Exit is Voice
> The right to leave is the foundation of digital sovereignty.

---

## Related Projects

- [libertaria.app](https://libertaria.app) — Project website and blog
- [Citadel](https://github.com/MarkusMaiwald/citadel) — Validator deployment (Dlabs)

---

*Forge burns bright. The Exit is being built.*

⚡️
