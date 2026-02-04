# Libertaria SDK

> Sovereign Infrastructure for Autonomous Agents

[![Tests](https://img.shields.io/badge/tests-166%2F166%20passing-success)](https://github.com/MarkusMaiwald/libertaria-sdk)
[![Zig](https://img.shields.io/badge/Zig-0.15.2-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT%20%2B%20Commons%20Clause-blue)](LICENSE)

**Sovereign; Kinetic; Anti-Fragile.**

---

## What is Libertaria?

Libertaria is a stack for building sovereign agent networks — systems where:
- **Exit is Voice**: Cryptographic guarantees, not platform promises
- **Profit is Honesty**: Economic incentives align with truth
- **Code is Law**: Protocols, not platforms, govern behavior

This SDK implements the **L1 Identity Layer** with:
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
