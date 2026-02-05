# Libertaria SDK

> Sovereign Infrastructure for Autonomous Agents

[![Tests](https://img.shields.io/badge/tests-166%2F166%20passing-success)](https://github.com/MarkusMaiwald/libertaria-sdk)
[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-blue)](LICENSE)

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

**4. Post-Quantum by Default**
Cryptographic signatures that survive the quantum era are not a future upgrade — they are table stakes. We don't wait for NIST standards to settle; we implement and adapt.

**5. AI as First-Class Citizen**
Agents are not chatbots bolted onto legacy systems. They are sovereign actors with identity, reputation, and capability. Our stack is built for a world where humans and AI coexist as peers.

**6. The Kenya Rule**
If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all. We optimize for minimal resource consumption, offline-first operation, and maximum accessibility.

**7. Interplanetary by Necessity**
Humanity's future is multi-planetary. We build systems that function across light-minutes of delay, that synchronize asynchronously, that work when Earth is on the other side of the Sun.

**8. Protocols Over Platforms**
We don't build walled gardens. We build open protocols that anyone can implement, extend, or fork. The value is in the network, not in our servers.

**9. Trust But Verify**
Cryptographic proof, not platform promises. Reputation graphs, not follower counts. Transparent incentives, not hidden algorithms.

**10. Code is Speech, Exit is Voice**
We defend the right to build, to experiment, to fork, and to leave. Technology is a tool of liberation — never of control.

### This SDK

This repository implements the **L1 Identity Layer** with:
- Ed25519 sovereign identities with rotation/burn
- Trust Graph (QVL) with betrayal detection
- GQL (ISO/IEC 39075:2024 compliant) query interface
- Persistent storage with Kenya Rule compliance

---

## Quick Start

```bash
# Clone
git clone https://github.com/MarkusMaiwald/libertaria-sdk.git
cd libertaria-sdk

# Build
zig build

# Test (166/166 passing)
zig build test
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
├─────────────────────────────────────────────────────────────┤
│                    Libertaria SDK                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Identity   │  │  Trust Graph │  │    GQL       │      │
│  │  (identity)  │  │    (qvl)     │  │  (gql/*.zig) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
├─────────────────────────────────────────────────────────────┤
│                    Janus Standard Library                    │
├─────────────────────────────────────────────────────────────┤
│                    Janus Compiler (:service)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Modules

### Identity (`l1-identity/`)
- `crypto.zig` — Ed25519 signatures, key rotation
- `did.zig` — Decentralized identifiers
- `soulkey.zig` — Deterministic key derivation
- `entropy.zig` — Sovereign randomness

### QVL — Quasar Vector Lattice (`l1-identity/qvl/`)
- `storage.zig` — PersistentGraph with libmdbx
- `betrayal.zig` — Bellman-Ford negative cycle detection
- `pathfinding.zig` — A* trust path discovery
- `feed.zig` — L4 temporal event store (DuckDB + LanceDB)
- `gql/` — ISO/IEC 39075:2024 Graph Query Language
  - `lexer.zig` — Tokenizer
  - `parser.zig` — Recursive descent parser
  - `ast.zig` — Abstract syntax tree
  - `codegen.zig` — GQL → Zig transpiler

---

## GQL Example

```zig
const gql = @import("qvl").gql;

// Parse GQL query
const query_str = "MATCH (n:Identity)-[t:TRUST]->(m) WHERE n.did = 'alice' RETURN m";
var query = try gql.parse(allocator, query_str);
defer query.deinit();

// Transpile to Zig code
const zig_code = try gql.generateZig(allocator, query);
defer allocator.free(zig_code);
```

---

## Kenya Compliance

| Metric | Target | Status |
|--------|--------|--------|
| Binary Size (L1) | < 200KB | ✅ 85KB |
| Memory Usage | < 10MB | ✅ ~5MB |
| Storage | Single-file | ✅ libmdbx |
| Cloud Calls | None | ✅ Offline-capable |

---

## Testing

```bash
# All tests
zig build test

# Specific module
zig test l1-identity/qvl/gql/lexer.zig
zig test l1-identity/qvl/storage.zig
```

**Current Status:** 166/166 tests passing ✅

---

## Related Projects

- [Janus Language](https://github.com/janus-lang/janus) — The foundation
- [libertaria.blog](https://github.com/MarkusMaiwald/libertaria-blog) — This project's blog
- [libertaria.bot](https://github.com/MarkusMaiwald/libertaria-bot) — Agent marketplace (coming soon)

---

## Philosophy

### Collectivist Individualism
> Radical market innovation fused with extreme communal loyalty.

### The Kenya Rule
> If it doesn't run on a $5 Raspberry Pi, it doesn't run at all.

### Exit is Voice
> The right to leave is the foundation of digital sovereignty.

---

## License

MIT License + Libertaria Commons Clause

See [LICENSE](LICENSE) for details.

---

*Forge burns bright. The Exit is being built.*

⚡️
