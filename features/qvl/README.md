# QVL BDD Test Suite

## Overview
This directory contains Gherkin feature specifications for the Quasar Vector Lattice (QVL) - L1 trust graph engine.

**Status:** Sprint 0 — Specification Complete  
**Next:** Implement step definitions in Zig

---

## Feature Files

| Feature | Scenarios | Purpose |
|---------|-----------|---------|
| `trust_graph.feature` | 8 | Core graph operations (add/remove/query edges) |
| `betrayal_detection.feature` | 8 | Bellman-Ford negative cycle detection |
| `pathfinding.feature` | 10 | A* reputation-guided pathfinding |
| `gossip_protocol.feature` | 10 | Aleph-style probabilistic flooding |
| `belief_propagation.feature` | 8 | Bayesian inference over trust DAG |
| `pop_reputation.feature` | 14 | PoP verification + reputation scoring |

**Total:** 58 scenarios covering all QVL functionality

---

## Key Testing Principles

### Kenya Rule Compliance
Every feature includes performance scenarios:
- Memory usage < 10MB
- Execution time benchmarks for O(|V|×|E|) algorithms
- Bandwidth limits for gossip

### Security Coverage
- Betrayal detection (negative cycles)
- Eclipse attack resilience
- Replay protection (entropy stamps)
- Signature verification

### Integration Points
- PoP (Proof-of-Path) verification
- Reputation decay over time
- RiskGraph → CompactTrustGraph mapping

---

## Running Tests

### Future: Zig Implementation
```bash
# Run all QVL tests
zig build test-qvl

# Run specific feature
zig build test -- --feature betrayal_detection

# Run with coverage
zig build test-qvl-coverage
```

### Current: Documentation Phase
These features serve as:
1. **Specification** — What QVL should do
2. **Acceptance Criteria** — When we're done
3. **Documentation** — How it works
4. **Test Template** — For Zig implementation

---

## GQL Integration (Future)

When GQL Parser is implemented:
```gherkin
Scenario: GQL query for trust path
  When I execute GQL "MATCH (a:Identity)-[t:TRUST*1..3]->(b:Identity) WHERE a.did = 'did:alice' RETURN b"
  Then I should receive reachable nodes within 3 hops
```

---

## Related Documentation

- `../l1-identity/qvl/` — Implementation (Zig)
- `../../docs/L4-hybrid-schema.md` — L4 Feed schema
- RFC-0120 — QVL Specification

---

**Maintainer:** Frankie (Silicon Architect)  
**Last Updated:** 2026-02-03

⚡️
