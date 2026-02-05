# DECISIONS.md — Architecture Decision Records

*Why Libertaria is built the way it is*

---

## ADR-001: Zig over Rust (2024-06-15)

### Context
We needed a systems language for L0-L4 with explicit control, no runtime, and cross-compilation support.

### Options Considered
- **Rust** — Memory safety, large ecosystem
- **C** — Universal, but unsafe by default
- **Go** — Easy concurrency, but GC and large binaries
- **Zig** — Explicit control, comptime, C interop

### Decision
Choose **Zig**.

### Rationale
1. **No hidden costs** — Allocators explicit, no hidden allocations
2. **Comptime** — Zero-cost abstractions without macros
3. **C interop** — Direct use of libsodium, OpenSSL, liboqs
4. **Cross-compilation** — Single toolchain, all targets
5. **Simplicity** — Smaller mental model than Rust

### Consequences
- Smaller ecosystem (we build more ourselves)
- Fewer developers know Zig (steeper onboarding)
- Better control over binary size (Kenya Rule compliance)

### Status
✅ Accepted — Core stack written in Zig

---

## ADR-002: No Blockchain (2024-07-01)

### Context
Every "Web3" project defaults to blockchain. We questioned this assumption.

### Options Considered
- **Ethereum L2** — Ecosystem, but 15 TPS, fees, complexity
- **Solana** — Fast, but validator requirements (cost, centralization)
- **Custom chain (Substrate)** — Flexible, but still chain constraints
- **No chain** — Direct peer-to-peer, offline-first

### Decision
Choose **No Blockchain**.

### Rationale
1. **Chains are slow databases** — We need real-time messaging
2. **Consensus is expensive** — Proof of Work/Stake wastes energy
3. **Validator capture** — Economic power → political power
4. **Offline-first** — Chains require connectivity

### What We Use Instead
- **QVL** — Trust graph for reputation
- **SoulKey** — Cryptographic identity without ledger
- **MIMIC** — Censorship resistance without consensus
- **Chapter federation** — Coordination without global state

### Consequences
- No "number go up" tokenomics
- Harder to explain ("what's your token?")
- True sovereignty (no validator set to capture)

### Status
✅ Accepted — Protocols work without chain

---

## ADR-003: Post-Quantum by Default (2024-08-10)

### Context
Quantum computers will break RSA/ECC. NIST is standardizing PQC algorithms.

### Options Considered
- **Wait for NIST finalization** — Safe, but slow
- **Implement draft standards** — Risky, but prepared
- **Hybrid (classical + PQC)** — Conservative, but complex

### Decision
Choose **Implement draft standards with hybrid fallback**.

### Rationale
1. **Cryptographic agility** — Can upgrade algorithms
2. **PQXD handshakes** — X25519 + Kyber-768 hybrid
3. **FIPS 202 compliance** — SHA-3, SHAKE already standardized

### Implementation
- `core/l1-identity/crypto.zig` — Algorithm selection
- `vendor/liboqs/` — Open Quantum Safe library
- Fallback to classical if PQC fails

### Consequences
- Larger binary (PQC algorithms)
- Slower handshakes (hybrid)
- Future-proof (survives quantum era)

### Status
✅ Accepted — PQXDH implemented

---

## ADR-004: MIMIC over VPN (2024-09-01)

### Context
VPNs are blocked by DPI. Tor is fingerprinted. We need traffic that looks "normal."

### Options Considered
- **Obfs4** — Tor pluggable transport
- **Shadowsocks** — Simple, but fingerprintable
- **Steganography** — Hide in images/video
- **MIMIC** — Protocol camouflage

### Decision
Choose **MIMIC (Multiple Identity Masking with Intelligent Camouflage)**.

### Rationale
1. **Traffic shaping** — Match real-world distributions
2. **Protocol skins** — HTTPS, DNS, QUIC camouflage
3. **Polymorphic** — Per-session parameters
4. **Active evasion** — Adapt to probing

### Implementation
- `core/l0-transport/mimic_*.zig` — Skin implementations
- `core/l0-transport/png.zig` — Polymorphic noise generator
- Deterministic padding (both peers calculate same)

### Consequences
- Complex (must implement full protocol stacks)
- Resource intensive (traffic shaping)
- Highly effective (indistinguishable from normal traffic)

### Status
✅ Accepted — MIMIC_HTTPS implemented

---

## ADR-005: Tiered Licensing (2024-10-15)

### Context
We need to protect the protocol while enabling business adoption.

### Options Considered
- **MIT** — Maximum adoption, but enables capture
- **GPL** — Viral, but SaaS loophole
- **AGPL** — Closes SaaS loophole, but toxic to business
- **Custom tiered** — Core protected, SDK business-friendly

### Decision
Choose **Three-tier licensing**.

### Tiers
1. **LCL-1.0 (Commonwealth)** — Core (L0-L3)
   - Viral reciprocity
   - SaaS loophole closed
   - Patent disarmament

2. **LSL-1.0 (Sovereign)** — SDK (L4+)
   - File-level reciprocity
   - Build proprietary apps
   - Patent peace

3. **LUL-1.0 (Unbound)** — Docs/Examples
   - Attribution only
   - Maximum spread

### Rationale
1. **Protocol protection** — Core can't be captured
2. **Business enablement** — Build on SDK without infection
3. **No CLA** — Contributors keep copyright

### Consequences
- Complex (three licenses to understand)
- Novel (untested in court)
- Principled (matches our values)

### Status
✅ Accepted — All files have SPDX headers

---

## ADR-006: Exit-First Governance (2024-11-01)

### Context
Democracy and corporate governance both fail at scale. We need a third way.

### Options Considered
- **Liquid democracy** — Delegation, but capture possible
- **Futarchy** — Prediction markets, but complex
- **Chapter federation** — Local sovereignty + federation

### Decision
Choose **Chapter Federation with Exit-First Design**.

### Rationale
1. **Local sovereignty** — Each chapter owns its state
2. **Federation** — Coordinate without global consensus
3. **Forkability** — Any chapter can split cleanly
4. **Betrayal economics** — Defection is expensive

### Implementation
- `core/l2-federation/` — Bridge protocol
- `core/l3-governance/` — Chapter mechanics
- QVL for cross-chapter trust

### Consequences
- No "official" version (many forks possible)
- Loyalty must be earned (can't enforce)
- Resilient (no single point of failure)

### Status
✅ Accepted — Chapter protocol in design

---

## ADR-007: Kenya Rule (2024-12-01)

### Context
Infrastructure that only runs in data centers isn't sovereign. We need edge compatibility.

### Options Considered
- **Cloud-first** — Easy, but requires connectivity
- **Edge-first** — Harder, but works offline
- **Kenya Rule** — Must run on minimal hardware

### Decision
Choose **Kenya Rule as constraint**.

### Definition
> "If it doesn't run on a solar-powered phone in Mombasa, it doesn't run at all."

### Metrics
- Binary size: < 200KB (L0-L1)
- Memory: < 10MB
- Storage: Single-file (libmdbx)
- Cloud calls: Zero (offline-capable)

### Consequences
- Feature constraints (can't use heavy libraries)
- Optimization focus (every byte matters)
- Universal accessibility (works anywhere)

### Status
✅ Accepted — 85KB binary achieved

---

## ADR-008: AI as First-Class (2025-01-15)

### Context
Agents are becoming actors in systems. Most infrastructure treats them as tools.

### Options Considered
- **Tool model** — Agents as extensions of humans
- **Actor model** — Agents as independent entities
- **Hybrid** — Context-dependent sovereignty

### Decision
Choose **AI as First-Class Sovereign Actors**.

### Rationale
1. **Cryptographic identity** — Agents have DIDs
2. **Reputation** — QVL tracks agent trust
3. **Capability-based** — Permissions, not blanket access
4. **Exit rights** — Agents can migrate/fork

### Implementation
- `AGENT.md` — Agent-specific documentation
- Capability tokens in `core/l2-membrane/`
- Agent-oriented APIs

### Consequences
- Novel legal questions (agent liability)
- Complex trust models
- Future-proof (AI-native infrastructure)

### Status
✅ Accepted — Agent documentation published

---

## How to Propose a New ADR

1. **Open an issue** — Describe the decision needed
2. **Discuss** — Get feedback from maintainers
3. **Draft ADR** — Follow this format
4. **PR** — Submit for review
5. **Decide** — Accept, reject, or defer

### ADR Template

```markdown
# ADR-XXX: Title (YYYY-MM-DD)

## Context
What is the problem?

## Options Considered
- Option A — Pros/cons
- Option B — Pros/cons

## Decision
What we chose.

## Rationale
Why we chose it.

## Consequences
What this means.

## Status
- [ ] Proposed
- [ ] Accepted
- [ ] Deprecated
```

---

*These decisions define us. Challenge them as we grow.*

⚡️
