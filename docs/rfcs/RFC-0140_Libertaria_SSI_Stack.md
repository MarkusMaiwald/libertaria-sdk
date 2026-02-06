# RFC-0140: Libertaria Self-Sovereign Identity (SSI) Stack

**Version:** 1.0.0-draft  
**Status:** Draft  
**Author:** Markus Maiwald, Libertaria Architects  
**Date:** 2026-02-06  
**Supersedes:** IOP Morpheus, W3C DID Core (extended)  

---

## Abstract

This specification defines the Libertaria Self-Sovereign Identity (SSI) Stack — a complete identity, trust, and coordination system for sovereign individuals and agents. Unlike blockchain-based identity systems, Libertaria SSI operates without global consensus, validators, or on-chain state, achieving censorship resistance through cryptographic sovereignty rather than distributed ledgers.

The stack comprises four protocol layers (L0-L3) plus application frameworks (L4+), addressing the four pillars of decentralized society: **Communication**, **Contracts/Law**, **Economy**, and **Decentralized Production**.

**Design Principles:**
- **Exit is Default:** Any participant can fork at any level without losing identity or history
- **Kenya Rule:** Runs on $5 Raspberry Pi; no cloud dependencies
- **No Blockchain:** Sovereignty through cryptography, not consensus
- **Interoperable:** W3C DID/VC compatible where standards exist

---

## Table of Contents

1. [Overview](#1-overview)
2. [The Four Pillars](#2-the-four-pillars)
3. [Layer 0-1: Identity & Trust (SoulKey + QVL)](#3-layer-0-1-identity--trust)
4. [Layer 2: Verifiable Credentials](#4-layer-2-verifiable-credentials)
5. [Layer 3: Smart Contracts without Chain](#5-layer-3-smart-contracts-without-chain)
6. [Layer 4: Chapter Federation](#6-layer-4-chapter-federation)
7. [`did:libertaria` Method Specification](#7-didlibertaria-method-specification)
8. [Security Considerations](#8-security-considerations)
9. [Privacy Considerations](#9-privacy-considerations)
10. [Implementation Status](#10-implementation-status)

---

## 1. Overview

### 1.1 The Problem with Blockchain Identity

Existing SSI solutions rely on:
- **Global consensus** (slow, expensive)
- **Validator sets** (capture possible)
- **On-chain state** (privacy leaks)
- **Token economics** (misaligned incentives)

Libertaria rejects these trade-offs.

### 1.2 The Libertaria Approach

| Component | Blockchain SSI | Libertaria SSI |
|:----------|:---------------|:---------------|
| **Root of Trust** | Validators | Cryptographic Keys (SoulKey) |
| **State Storage** | Global ledger | Local-first (Capsule nodes) |
| **Revocation** | On-chain bitmap | QVL Betrayal Detection |
| **Coordination** | Smart contracts | State channels + Chapters |
| **Availability** | 24/7 online | Offline-first (async sync) |

### 1.3 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│ L4: APPLICATIONS                                            │
│  • EuroSign (contracts)                                     │
│  • SzámlaŐr (invoices)                                      │
│  • Social coordination tools                                │
├─────────────────────────────────────────────────────────────┤
│ L3: GOVERNANCE (Chapter Federation)                         │
│  • State channels for contracts                             │
│  • Betrayal economics                                       │
│  • Exit-first coordination                                  │
├─────────────────────────────────────────────────────────────┤
│ L2: VERIFIABLE CREDENTIALS                                  │
│  • JSON-LD VCs                                              │
│  • Selective disclosure (BBS+)                              │
│  • ZK-proofs for privacy                                    │
├─────────────────────────────────────────────────────────────┤
│ L1: TRUST (QVL)                                             │
│  • Trust Graph with temporal decay                          │
│  • Betrayal detection (Bellman-Ford)                        │
│  • Reputation computation                                   │
├─────────────────────────────────────────────────────────────┤
│ L0: IDENTITY (SoulKey)                                      │
│  • Deterministic key derivation                             │
│  • Portable across contexts                                 │
│  • Burn capability (revocation)                             │
│  • did:libertaria method                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. The Four Pillars

### 2.1 Pillar 1: Communication

**Requirements:**
- End-to-end encrypted messaging
- Censorship-resistant transport
- Identity-verified contacts

**Libertaria Solution:**
- L0 Transport (MIMIC skins, Noise Protocol)
- L0 Identity (SoulKey for key exchange)
- L1 Trust (QVL for contact verification)

### 2.2 Pillar 2: Contracts & Law

**Requirements:**
- Legally binding agreements
- Verifiable signatures
- Dispute resolution

**Libertaria Solution:**
- L2 VCs (legal identity verification)
- L3 State channels (smart contracts without chain)
- L3 QTSP integration (qualified signatures where required)

### 2.3 Pillar 3: Economy

**Requirements:**
- Value transfer
- Reputation tracking
- Low transaction costs

**Libertaria Solution:**
- L1 QVL (trust scores as economic signal)
- L3 State channels (instant settlement)
- Capability tokens (not speculative coins)

### 2.4 Pillar 4: Decentralized Production

**Requirements:**
- Open hardware specs
- Local manufacturing
- Supply chain coordination

**Libertaria Solution:**
- L4 Open Specs (documented, forkable)
- L4 Local First (Kenya Rule)
- L3 Chapter Federation (coordination without centralization)

---

## 3. Layer 0-1: Identity & Trust

### 3.1 SoulKey (L0)

**Purpose:** Deterministic, hierarchical key derivation for self-sovereign identity.

**Algorithm:**
```
Root Key = Argon2id(seed, salt, params)
SoulKey(context) = HKDF-SHA3-256(Root Key, context, length=32)
DID = did:libertaria:multibase(base58btc, BLAKE3-256(SoulKey("identity")))
```

**Properties:**
- **Deterministic:** Same seed + context = same keys
- **Hierarchical:** Unlimited derived keys from single seed
- **Context-separated:** Work, family, hobby identities are cryptographically unlinkable
- **Recoverable:** Cold wallet backup (BIP-39 mnemonic)

**Key Types:**
| Type | Algorithm | Purpose |
|:-----|:----------|:--------|
| Authentication | Ed25519 | DID authentication, signatures |
| Agreement | X25519 | Key exchange, encryption |
| Assertion | Ed25519 | VC issuance |
| Capability | Ed25519 | Authorization tokens |

### 3.2 QVL — Quasar Vector Lattice (L1)

**Purpose:** Decentralized trust graph with betrayal detection.

**Data Model:**
```rust
pub struct TrustEdge {
    pub source: DidId,           // Who trusts
    pub target: DidId,           // Who is trusted
    pub weight: f64,             // -1.0 (distrust) to +1.0 (trust)
    pub timestamp: Timestamp,    // When established
    pub decay_rate: f64,         // Temporal decay (half-life)
    pub proof: Option<Signature>, // Cryptographic attestation
}

pub struct TrustGraph {
    pub edges: Vec<TrustEdge>,
    pub nodes: HashSet<DidId>,
}
```

**Betrayal Detection:**
- **Algorithm:** Bellman-Ford negative cycle detection
- **Purpose:** Identify trust loops where defection is profitable
- **Output:** `BetrayalRisk` score per DID

**Trust Score Computation:**
```rust
fn compute_trust(graph: &TrustGraph, source: DidId, target: DidId) -> TrustScore {
    // 1. Find all paths from source to target
    let paths = graph.find_all_paths(source, target, max_depth=6);
    
    // 2. Compute path weights (with temporal decay)
    let path_scores: Vec<f64> = paths.iter()
        .map(|p| p.edges.iter()
            .map(|e| e.weight * temporal_decay(e.timestamp))
            .product())
        .collect();
    
    // 3. Aggregate (parallel resistance model)
    TrustScore::aggregate(path_scores)
}
```

**Properties:**
- **Local-first:** Each node maintains own view of graph
- **Gossip-based:** Edges propagate via epidemic broadcast
- **Privacy-preserving:** Trust relationships are shared, not identity metadata

---

## 4. Layer 2: Verifiable Credentials

### 4.1 VC Data Model

**W3C Compatibility:**
- JSON-LD format
- `@context` for semantic interoperability
- `proof` field for cryptographic verification

**Example:**
```json
{
  "@context": ["https://www.w3.org/2018/credentials/v1"],
  "id": "urn:uuid:12345678-1234-1234-1234-123456789012",
  "type": ["VerifiableCredential", "ProfessionalLicense"],
  "issuer": "did:libertaria:z8m9n0p2q4r6s8t0...",
  "issuanceDate": "2026-02-06T00:00:00Z",
  "credentialSubject": {
    "id": "did:libertaria:z7k8j9m3n5p2q4r...",
    "profession": "Software Architect",
    "licenseNumber": "EUDI-DE-2026-001"
  },
  "proof": {
    "type": "Ed25519Signature2020",
    "created": "2026-02-06T00:00:00Z",
    "proofPurpose": "assertionMethod",
    "verificationMethod": "did:libertaria:z8m9n...#key-1",
    "proofValue": "z58D..."
  }
}
```

### 4.2 Selective Disclosure

**BBS+ Signatures:**
- Signer commits to set of attributes
- Prover can reveal subset without exposing all
- Zero-knowledge proof of non-revocation

**Use Case:** Prove "over 18" without revealing birthdate.

### 4.3 Revocation

**No Global Registry:**
- Issuer maintains private revocation list
- Prover provides non-revocation proof (accumulator-based)
- No on-chain state required

**Accumulator:**
```rust
pub struct RevocationAccumulator {
    pub current: AccumulatorValue,
    pub witness: MembershipWitness,  // For non-revoked credentials
}
```

---

## 5. Layer 3: Smart Contracts without Chain

### 5.1 The Problem with On-Chain Contracts

- **Cost:** Gas fees make micro-contracts uneconomical
- **Speed:** Block times prevent real-time coordination
- **Privacy:** All state is public
- **Lock-in:** Platform dependency

### 5.2 State Channels

**Concept:**
- Parties lock collateral in multi-sig
- Execute contract off-chain (instant, private)
- Settle final state on-chain (if needed) or via L4 Chapter

**Libertaria Innovation:** No chain required for settlement.

**Mechanism:**
```rust
pub struct StateChannel {
    pub participants: Vec<DidId>,
    pub state: ContractState,
    pub sequence: u64,           // Monotonic version
    pub signatures: Vec<Signature>, // All participants must sign
    pub dispute_deadline: Timestamp,
}

impl StateChannel {
    fn update(&mut self, new_state: ContractState) -> Result<(), ChannelError> {
        // All participants sign
        // Old state invalidated by sequence number
        // If dispute: submit to L3 Chapter arbitration
    }
}
```

**Settlement Options:**
1. **Mutual:** All parties sign final state
2. **Arbitration:** L3 Chapter adjudicates disputes
3. **Timeout:** Pre-signed exit states execute automatically

### 5.3 Betrayal Economics

**Principle:** Defection must be economically irrational.

**Mechanism:**
- Participants stake collateral in channel
- QVL trust score determines stake multiplier
- Defection burns stake, distributes to honest parties
- Reputation cost > financial gain

**Formula:**
```
Defection_Cost = Stake * (1 + Trust_Score) + Reputation_Loss
Defection_Gain = Immediate_Payoff
Rational_Actor_Defects: Defection_Gain > Defection_Cost
Libertaria_Ensures: Defection_Cost > Defection_Gain (by construction)
```

### 5.4 Legal Binding

**Qualified Electronic Signatures (QES):**
- Integration with licensed QTSPs (where required)
- HSM-backed signing (private keys never leave hardware)
- eIDAS 2.0 compliant

**Smart Legal Contracts:**
- Ricardian contracts (human-readable + machine-executable)
- Natural language binding
- Enforceable in traditional courts

---

## 6. Layer 4: Chapter Federation

### 6.1 Chapters

**Definition:** Local sovereign communities with transparent governance.

**Structure:**
```rust
pub struct Chapter {
    pub id: ChapterId,
    pub charter: Constitution,       // Written rules
    pub members: Vec<DidId>,
    pub reputation_threshold: f64,   // Minimum QVL score to join
    pub governance: GovernanceModel,
}

pub enum GovernanceModel {
    Direct,           // One member, one vote
    Liquid,           // Delegated voting
    Meritocratic,     // Weighted by QVL score
    None,             // Anarchy (coordination only)
}
```

### 6.2 Exit-First Design

**Any member can:**
- Fork the Chapter (take copy of state, leave)
- Exit with assets (no penalty)
- Join multiple Chapters
- Create sub-Chapters

**No Global Consensus:**
- Chapters are independent
- Federation via mutual recognition
- Disputes resolved by overlapping Chapter membership

### 6.3 Coordination without Centralization

**Cross-Chapter Contracts:**
- State channels span Chapters
- Reputation is portable (QVL graph includes cross-Chapter edges)
- Arbitration by mutually-trusted third Chapter

**Production Coordination:**
- Open hardware specs (documented in Chapter repos)
- Local manufacturing (Kenya Rule)
- Quality attestation via QVL (reputation-based)

---

## 7. `did:libertaria` Method Specification

### 7.1 Method Name

```
did:libertaria
```

### 7.2 Method-Specific Identifier

```
did:libertaria:<method-specific-id>
```

**Algorithm:**
```
initial_key = SoulKey(seed, context="identity")
method-specific-id = multibase(base58btc, BLAKE3-256(initial_key.public_key))
```

**Example:**
```
did:mosaic:z7k8j9m3n5p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2f4g6h8
did:libertaria:z8m9n0p2q4r6s8t0u2v4w6x8y0z2a4b6c8d0e2f4g6h8i0
```

### 7.3 Versioning

**Implicit (Latest):**
```
did:libertaria:z8m9n0p2q4r...
```

**Explicit:**
```
did:libertaria:z8m9n0p2q4r...?versionId=2.1
did:libertaria:z8m9n0p2q4r...?versionTime=2026-02-06T12:00:00Z
```

**Resolution:**
- Client fetches DID Document
- If `versionId` specified, returns historical version
- If unspecified, returns latest
- Backward compatibility maintained via `versionId`

### 7.4 DID Document

**Format:**
```json
{
  "@context": ["https://www.w3.org/ns/did/v1", "https://libertaria.app/ns/did/v1"],
  "id": "did:libertaria:z8m9n0p2q4r...",
  "verificationMethod": [
    {
      "id": "did:libertaria:z8m9n0p2q4r...#auth-1",
      "type": "Ed25519VerificationKey2020",
      "controller": "did:libertaria:z8m9n0p2q4r...",
      "publicKeyMultibase": "z6Mk..."
    }
  ],
  "authentication": ["did:libertaria:z8m9n0p2q4r...#auth-1"],
  "assertionMethod": ["did:libertaria:z8m9n0p2q4r...#assert-1"],
  "keyAgreement": ["did:libertaria:z8m9n0p2q4r...#key-1"],
  "service": [
    {
      "id": "did:libertaria:z8m9n0p2q4r...#capsule",
      "type": "CapsuleNode",
      "serviceEndpoint": "https://capsule.libertaria.app/z8m9n..."
    }
  ],
  "qvl": {
    "trustScore": 0.87,
    "betrayalRisk": "low",
    "chapters": ["chapter://berlin/core", "chapter://budapest/dev"]
  }
}
```

### 7.5 Operations

| Operation | Mechanism | On-Chain? |
|:----------|:----------|:----------|
| **Create** | SoulKey derivation | No |
| **Read** | Local resolution + QVL gossip | No |
| **Update** | Key rotation (self-signed) | No |
| **Deactivate** | Tombstone document + QVL propagation | No |

**No blockchain required for any operation.**

---

## 8. Security Considerations

### 8.1 Key Management

- **Cold Storage:** BIP-39 mnemonic for recovery
- **Hot Keys:** Derived per-context, revocable
- **HSM:** For QES and high-value operations
- **Rotation:** Recommended every 90 days for active keys

### 8.2 Trust Attacks

**Sybil Resistance:**
- QVL requires genuine interaction for trust edges
- Betrayal detection identifies coordinated fake identities
- Chapter membership requires reputation threshold

**Eclipse Attacks:**
- Gossip protocol with random peer selection
- Multiple bootstrap nodes
- Trusted contact lists for initial sync

### 8.3 Quantum Resistance

- **Current:** Ed25519 + X25519 (classical secure)
- **Migration:** PQXDH (X25519 + Kyber-768 hybrid)
- **Future:** Dilithium3 for signatures, Kyber for key exchange

---

## 9. Privacy Considerations

### 9.1 Unlinkability

- **SoulKey Contexts:** Work, personal, hobby identities are cryptographically unlinkable
- **BBS+ Selective Disclosure:** Reveal minimum necessary
- **MIMIC Transport:** Traffic analysis resistant

### 9.2 Metadata Protection

- **No Global Registry:** No central point of correlation
- **Local-First:** Data stays on device unless explicitly shared
- **QVL Edges:** Trust relationships visible, metadata private

### 9.3 Right to be Forgotten

- **Burn Capability:** DID deactivation irreversible
- **VC Revocation:** Accumulator-based, no history leak
- **Chapter Exit:** Take data, leave no trace

---

## 10. Implementation Status

| Component | Status | Location |
|:----------|:-------|:---------|
| SoulKey | ✅ Stable | `core/l1-identity/soulkey.zig` |
| QVL Core | ✅ Stable | `core/l1-identity/qvl/` |
| Betrayal Detection | ✅ 47/47 tests passing | `core/l1-identity/qvl/betrayal.zig` |
| `did:libertaria` | 🚧 In Progress | `core/l1-identity/did.zig` |
| VC Layer | 🚧 JSON-LD parser | `core/l2-vc/` |
| State Channels | 🚧 Design phase | `docs/rfcs/RFC-0141_State_Channels.md` |
| Chapter Federation | 🚧 Spec only | `docs/rfcs/RFC-0142_Chapters.md` |
| QTSP Integration | 📋 Planned | Post-V1 |

**Milestone:** V1.0 (Q3 2026) — SoulKey + QVL + basic VC layer

---

## References

- [W3C DID Core](https://www.w3.org/TR/did-core/)
- [W3C VC Data Model](https://www.w3.org/TR/vc-data-model-2.0/)
- [RFC-0015 Transport Skins](./RFC-0015_Transport_Skins.md)
- [IOP Morpheus Specification](https://github.com/Internet-of-People) (Lineage)
- [Kenya Rule Manifesto](https://libertaria.app/blog/2026-01-30-titania-reborn-the-kenya-rule/)

---

## Appendix A: Comparison with Other SSI Systems

| System | Blockchain | Global Consensus | Offline | Exit | Kenya Rule |
|:-------|:-----------|:-----------------|:--------|:-----|:-----------|
| **Bitcoin/ION** | ✅ Yes | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Ethereum/uPort** | ✅ Yes | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **Sovrin/Indy** | ✅ Yes | ✅ Yes | ❌ No | ❌ No | ❌ No |
| **ION (Sidetree)** | ✅ Yes | ⚠️ Anchored | ❌ No | ❌ No | ❌ No |
| **DID:Key** | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |
| **DID:Web** | ❌ No | ❌ No | ⚠️ Cached | ⚠️ Partial | ✅ Yes |
| **Libertaria** | ❌ No | ❌ No | ✅ Yes | ✅ Yes | ✅ Yes |

**Libertaria is the only system that achieves:**
- No blockchain dependency
- Full offline operation
- Exit as architectural primitive
- Kenya Rule compliance

---

*Forge burns bright. Identity is sovereign.*

🜏
