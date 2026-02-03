# Libertaria SDK for Janus

> Sovereign; Kinetic; Anti-Fragile.

**Version:** 0.2.0-alpha  
**Status:** Sprint 2 Complete (GQL Parser + Codegen)  
**License:** MIT + Libertaria Commons Clause

---

## Overview

The Libertaria SDK provides primitives for building sovereign agent networks on top of [Janus](https://github.com/janus-lang/janus) — the programming language designed for Carbon-Silicon symbiosis.

This SDK implements the **L1 Identity Layer** of the Libertaria Stack, featuring:

- **Cryptographic Identity** — Ed25519-based with rotation and burn capabilities
- **Trust Graph** — QVL (Quasar Vector Lattice) engine with betrayal detection
- **GQL (Graph Query Language)** — ISO/IEC 39075:2024 compliant query interface
- **Persistent Storage** — libmdbx backend with Kenya Rule compliance (<10MB)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                         │
│              (Your Agent / libertaria.bot)                   │
├─────────────────────────────────────────────────────────────┤
│                    Libertaria SDK                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Identity   │  │  Trust Graph │  │    GQL       │      │
│  │  (identity)  │  │    (qvl)     │  │  (gql/*.zig) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   Message    │  │   Context    │  │    Memory    │      │
│  │  (message)   │  │  (context)   │  │  (memory)    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
├─────────────────────────────────────────────────────────────┤
│                    Janus Standard Library                    │
├─────────────────────────────────────────────────────────────┤
│                    Janus Compiler (:service)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## Quick Start

### 1. Sovereign Identity

```janus
import libertaria.{identity}

// Create a new sovereign identity
let id = identity.create()

// Sign a message
let msg = bytes.from_string("Hello Sovereigns!")
let sig = identity.sign(id, msg)

// Verify signature
assert identity.verify(id, msg, sig)

// Rotate identity (new keys, linked provenance)
let (new_id, old_id) = identity.rotate(id)

// Burn identity (cryptographic deletion)
let burned = identity.burn(id)
```

### 2. Trust Graph (QVL)

```janus
import libertaria.{qvl}

// Create hybrid graph (persistent + in-memory)
let graph = qvl.HybridGraph.init(&persistent, allocator)

// Add trust edges
graph.addEdge(.{
  from = alice,
  to = bob,
  risk = -0.3,        // Negative = trust
  level = 3,          // Trust level 1-7
  timestamp = now(),
  expires_at = now() + duration.days(30)
})

// Detect betrayal rings (negative cycles)
let result = try graph.detectBetrayal(alice)
if result.betrayal_cycles.items.len > 0 {
  // Handle betrayal
}

// Find trust path
let path = try graph.findTrustPath(alice, charlie, 
  heuristic = qvl.reputationHeuristic,
  heuristic_ctx = &rep_map)
```

### 3. GQL (Graph Query Language)

```janus
import libertaria.{gql}

// Parse GQL query
let query_str = "MATCH (n:Identity)-[t:TRUST]->(m) WHERE n.did = 'alice' RETURN m"
let query = try gql.parse(allocator, query_str)
defer query.deinit()

// Transpile to Zig code
let zig_code = try gql.generateZig(allocator, query)
defer allocator.free(zig_code)

// Generated code looks like:
// pub fn execute(graph: *qvl.HybridGraph) !void {
//     // MATCH statement
//     // Traverse from n
//     var t = try graph.getOutgoing(n);
//     // Filter by type: TRUST
//     var m = t.to;
//     // WHERE n.did == "alice"
//     // RETURN statement
//     var results = std.ArrayList(Result).init(allocator);
//     defer results.deinit();
//     try results.append(m);
// }
```

---

## Module Reference

### `libertaria.identity`

| Function | Purpose |
|----------|---------|
| `create()` | Generate new Ed25519 identity |
| `rotate(id)` | Rotate keys with provenance chain |
| `burn(id)` | Cryptographic deletion |
| `sign(id, msg)` | Sign message |
| `verify(id, msg, sig)` | Verify signature |
| `is_valid(id)` | Check not revoked/expired |

### `libertaria.qvl`

| Type | Purpose |
|------|---------|
| `HybridGraph` | Persistent + in-memory graph |
| `PersistentGraph` | libmdbx-backed storage |
| `RiskGraph` | In-memory graph for algorithms |
| `GraphTransaction` | Batch operations |

| Function | Purpose |
|----------|---------|
| `detectBetrayal(source)` | Bellman-Ford negative cycle detection |
| `findTrustPath(src, tgt, heuristic)` | A* pathfinding |
| `addEdge(edge)` | Add trust edge |
| `getOutgoing(node)` | Get neighbors |

### `libertaria.gql`

| Function | Purpose |
|----------|---------|
| `parse(allocator, query)` | Parse GQL string to AST |
| `generateZig(allocator, query)` | Transpile to Zig code |

---

## GQL Syntax

### MATCH — Pattern Matching

```gql
-- Simple node
MATCH (n:Identity)

-- Node with properties
MATCH (n:Identity {did: 'alice', active: true})

-- One-hop traversal
MATCH (a)-[t:TRUST]->(b)

-- Variable-length path
MATCH (a)-[t:TRUST*1..3]->(b)

-- With WHERE clause
MATCH (n:Identity)-[t:TRUST]->(m)
WHERE n.did = 'alice' AND t.level >= 3
RETURN m
```

### CREATE — Insert Data

```gql
-- Create node
CREATE (n:Identity {did: 'alice'})

-- Create edge
CREATE (a)-[t:TRUST {level: 3}]->(b)

-- Create pattern
CREATE (a:Identity)-[t:TRUST]->(b:Identity)
```

### DELETE — Remove Data

```gql
-- Delete nodes
MATCH (n:Identity)
WHERE n.did = 'compromised'
DELETE n
```

### RETURN — Project Results

```gql
-- Return variable
MATCH (n) RETURN n

-- Return multiple
MATCH (a)-[t]->(b) RETURN a, t, b

-- With alias
MATCH (n) RETURN n.did AS identity

-- Aggregations (planned)
MATCH (n) RETURN count(n) AS total
```

---

## Design Principles

### 1. Exit is Voice

Agents can leave, taking their data cryptographically:

```janus
// Burn identity
let burned = identity.burn(my_id)
// After burn: no new signatures possible
// Verification of historical signatures still works
```

### 2. Profit = Honesty

Economic stakes align incentives:

- **Posting** requires $SCRAP burn
- **Identity** requires $STASIS bond
- **Reputation** decays without verification

### 3. Code is Law

No central moderation, only protocol rules:

- **Betrayal detection** via Bellman-Ford (mathematical, not subjective)
- **Path verification** via cryptographic proofs
- **Reputation** via Bayesian updates

### 4. Kenya Compliance

Resource-constrained environments:

- **Binary size:** <200KB for L1
- **Memory:** <10MB for graph operations
- **Storage:** Single-file embedded (libmdbx)
- **No cloud calls:** Fully offline-capable

---

## Testing

```bash
# Run all SDK tests
zig build test-qvl

# Run specific module
zig build test -- --module lexer

# Run with coverage (planned)
zig build test-qvl-coverage
```

---

## Roadmap

### Sprint 0 ✅ — BDD Specifications
- 58 Gherkin scenarios for QVL

### Sprint 1 ✅ — Storage Layer
- libmdbx PersistentGraph
- HybridGraph (disk + memory)

### Sprint 2 ✅ — GQL Parser
- ISO/IEC 39075:2024 compliant
- Lexer, Parser, AST, Codegen

### Sprint 3 🔄 — Documentation
- API reference (this file)
- Architecture decision records
- Tutorial: Building your first agent

### Sprint 4 📅 — L4 Feed
- DuckDB integration
- LanceDB vector store
- Social media primitives

### Sprint 5 📅 — Production
- Performance benchmarks
- Security audit
- Release v1.0

---

## Related Projects

- [Janus Language](https://github.com/janus-lang/janus) — The foundation
- [Libertaria Stack](https://git.maiwald.work/Libertaria) — Full protocol implementation
- [Moltbook](https://moltbook.com) — Agent social network (lessons learned)

---

## License

MIT License + Libertaria Commons Clause

See LICENSE for details.

---

*Forge burns bright. The Exit is being built.*

⚡️
