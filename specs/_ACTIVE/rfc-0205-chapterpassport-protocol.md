# RFC-0205: ChapterPassport Protocol

**Status:** DRAFT  
**Version:** 0.1.0  
**Layer:** L1.5 (Identity-Economics Bridge)  
**Class:** FOUNDATIONAL / CREDENTIAL  
**Author:** Markus Maiwald  
**Date:** 2026-02-04  
**Depends On:** RFC-0120 (QVL), RFC-0130 (ZK-STARK), RFC-0200 (Chapter Genesis), RFC-0630 (TBT), RFC-0648 (Hamiltonian Dynamics)  

---

> **The ChapterPassport is the Nexus where Identity, Economics, and Governance converge.**  > **Not just an exit document—a living credential for sovereign citizenship.**

---

## 1. ABSTRACT

The ChapterPassport is Libertaria's universal credential document. It serves as:

1. **LIVE IDENTITY CREDENTIAL**
   - Proof of Chapter membership
   - Reputation attestation (ZK-STARK)
   - Trust distance to arbitrary targets

2. **ECONOMIC PASSPORT**
   - TBT Balance commitment
   - Energy Token standing
   - Mint Window qualification (RFC-0648)
   - Velocity contribution proof

3. **EXIT DOCUMENT**
   - Portable reputation
   - Token export (per Chapter policy)
   - Endorsements from members
   - Anchored exit proof

4. **ENTRY CREDENTIAL**
   - Cross-Chapter migration
   - Federation trust transfer
   - Reputation import negotiation

---

## 2. THE PASSPORT STRUCTURE

```rust
/// The complete ChapterPassport
struct ChapterPassport {
    // ═══════════════════════════════════════════════════════
    // LAYER 1: IDENTITY CORE (Immutable)
    // ═══════════════════════════════════════════════════════
    /// User's primary identity
    soul_key: DID,
    /// Passport issuance
    issued_at: u64,
    issued_by: ChapterId,
    /// Cryptographic binding
    passport_id: [u8; 32], // Hash(soul_key || chapter || issued_at)
    
    // ═══════════════════════════════════════════════════════
    // LAYER 2: MEMBERSHIP STATUS (Live, updatable)
    // ═══════════════════════════════════════════════════════
    /// Current membership
    membership: MembershipStatus,
    /// Reputation (live snapshot)
    reputation: ReputationCredential,
    /// Trust graph position
    trust_position: TrustPositionCredential,
    
    // ═══════════════════════════════════════════════════════
    // LAYER 3: ECONOMIC STANDING (Live, updatable)
    // ═══════════════════════════════════════════════════════
    /// TBT accumulation
    tbt_credential: TBTCredential,
    /// Energy Token standing
    energy_credential: EnergyCredential,
    /// Velocity contribution (for Hamiltonian)
    velocity_credential: VelocityCredential,
    
    // ═══════════════════════════════════════════════════════
    // LAYER 4: SOCIAL ATTESTATIONS (Accumulated)
    // ═══════════════════════════════════════════════════════
    /// Endorsements from other members
    endorsements: Vec<Endorsement>,
    /// Contribution record
    contributions: ContributionRecord,
    /// Standing history
    standing_history: Vec<StandingEvent>,
    
    // ═══════════════════════════════════════════════════════
    // LAYER 5: ZK-STARK PROOFS (On-demand)
    // ═══════════════════════════════════════════════════════
    /// Pre-computed proofs (cached)
    cached_proofs: CachedProofs,
    /// Proof generation capability
    proof_generator: ProofGeneratorRef,
}
```

---

## 3. THE CREDENTIAL TYPES

### 3.1 ReputationCredential

```rust
struct ReputationCredential {
    /// Raw score (private to owner)
    score: f64,
    /// ZK-STARK: "rep ≥ threshold"
    threshold_proof: Option<StarkProof>,
    /// Last update
    updated_at: u64,
    /// Chapter signature
    chapter_attestation: Signature,
}
```

### 3.2 TBTCredential

```rust
struct TBTCredential {
    /// Raw balance (private)
    balance: f64,
    /// Accumulation start
    accumulating_since: u64,
    /// ZK-STARK: "balance ≥ X" or "balance ∈ [min, max]"
    balance_proof: Option<StarkProof>,
    /// Activity status
    is_active: bool,
}
```

### 3.3 VelocityCredential

```rust
struct VelocityCredential {
    /// Transactions in current epoch (private)
    tx_count: u64,
    /// Total value transacted (private)
    tx_volume: u64,
    /// ZK-STARK: "contributed ≥ X to velocity"
    contribution_proof: Option<StarkProof>,
    /// Qualifies for mint window?
    mint_window_eligible: bool,
}
```

### 3.4 TrustPositionCredential

```rust
struct TrustPositionCredential {
    /// Number of direct connections
    direct_connections: u32,
    /// Precomputed distances to key nodes
    cached_distances: HashMap<DID, u8>,
    /// ZK-STARK: "distance to X ≤ d"
    distance_proofs: HashMap<DID, StarkProof>,
}
```

---

## 4. HAMILTONIAN INTEGRATION

The Passport becomes the **key to the Velocity Economy**:

```rust
impl ChapterPassport {
    /// Check Mint Window eligibility
    fn check_mint_window_eligibility(
        &self,
        window: &MintWindow
    ) -> MintEligibility {
        // 1. Must be active member
        if !self.membership.is_active() {
            return MintEligibility::Denied("Not active");
        }
        
        // 2. Must satisfy identity maintenance
        if self.tbt_credential.maintenance_debt > THRESHOLD {
            return MintEligibility::Denied("Maintenance debt");
        }
        
        // 3. Generate ZK-STARK for eligibility
        let proof = self.proof_generator.generate(
            MembershipCircuit::new(
                &self.soul_key,
                &window.chapter_membership_root,
            )
        );
        
        MintEligibility::Eligible { proof }
    }
    
    /// Generate Velocity Contribution Proof
    fn prove_velocity_contribution(
        &self,
        epoch: Epoch,
        min_tx: u64
    ) -> Option<StarkProof> {
        if self.velocity_credential.tx_count < min_tx {
            return None; // Cannot prove falsehood
        }
        
        self.proof_generator.generate(
            VelocityContributionCircuit::new(
                epoch,
                min_tx,
                &self.velocity_credential,
            )
        )
    }
}
```

---

## 5. PASSPORT LIFECYCLE

```
1. GENESIS (Larval Bootstrap)
   User creates SoulKey (RFC-0250)
   Gets vouched into Chapter
   Chapter issues EMPTY Passport
   └─► passport_id = Hash(soul_key || chapter || now)

2. ACCUMULATION (Active Membership)
   TBT accrues: +1.0/epoch
   Reputation grows via interactions
   Trust graph expands via vouching
   Velocity tracked per epoch
   └─► Credentials UPDATE in place

3. ATTESTATION (On-Demand Proofs)
   User requests service requiring proof
   Passport generates ZK-STARK
   Proof cached for reuse
   └─► Service verifies WITHOUT seeing raw data

4. MIGRATION (Exit + Entry)
   User initiates exit
   Chapter FREEZES passport state
   Anchors exit proof to settlement chain
   User presents to new Chapter
   New Chapter verifies + imports
   └─► NEW passport issued; OLD marked "migrated"

5. DEATH (Key Compromise or Voluntary)
   User loses key OR exits network
   Passport marked "DECEASED"
   TBT non-transferable (dies with soul)
   Reputation history remains
   └─► Cannot be reactivated; only new Genesis
```

---

## 6. WHY RFC-0205 IS CRITICAL

| Without RFC-0205 | With RFC-0205 |
|------------------|---------------|
| Reputation Chapter-intern | Reputation **portable** |
| TBT dies at exit | TBT **Credential** travels |
| Hamiltonian needs custom logic | Hamiltonian uses **standard credential** |
| ZK-Proofs ad-hoc | ZK-Proofs **integrated** |
| Migration manual | Migration **automated** |

---

## 7. ARCHITECTURE

```
┌─────────────────────┐
│ RFC-0200            │
│ Chapter Genesis     │
│ (Constitution)      │
└──────────┬──────────┘
           │ defines
           ▼
┌─────────────────────────────────────────────┐
│ RFC-0205                                    │
│ CHAPTERPASSPORT                             │
│ (Citizen Credential)                        │
├─────────────────────────────────────────────┤
│                                             │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐        │
│ │RFC-0120 │ │RFC-0130 │ │RFC-0630 │        │
│ │ QVL     │ │ZK-STARK │ │ TBT     │        │
│ │ (Trust) │ │(Privacy)│ │ (Time)  │        │
│ └────┬────┘ └────┬────┘ └────┬────┘        │
│      │           │           │             │
│ └────┴───────────┴───────────┘             │
│              │                             │
│              ▼                             │
│    UNIFIED CREDENTIAL API                  │
│                                             │
└─────────────────────────────────────────────┘
```

---

## 8. CLOSING PRINCIPLES

> **The ChapterPassport is not a document—it is sovereignty made portable.**  > **Exit is guaranteed. Entry is negotiated. Identity is preserved.**  > **From Chapter to Chapter, the soul remains.**

---

**END RFC-0205 v0.1.0**
