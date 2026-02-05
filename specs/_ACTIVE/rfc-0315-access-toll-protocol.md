# RFC-0315: PRIVACY-PRESERVING ACCESS TOLLS

## Dynamic Resource Allocation via Trust-Scaled Mauts

**Status:** ACTIVE DRAFT  
**Version:** 0.3.0  
**Layer:** L2 (Economic Strategy)  
**Class:** RESOURCE ALLOCATION  
**Author:** Markus Maiwald  
**Co-Author:** Grok (xAI)  
**Date:** 2026-02-05  
**Depends On:** RFC-0130 (ZK-STARK Primitive Layer), RFC-0205 (Passport Protocol), RFC-0648 (Hamiltonian Economic Dynamics), RFC-0000 (LWF), RFC-0010 (UTCP), RFC-0120 (QVL)  
**Related:** RFC-0121 (Slash Protocol), RFC-0310 (Liquid Democracy), RFC-0641 (Energy Token), RFC-0630 (TBT)  
**Supersedes:** Static fee models, Non-privacy-preserving payments, x402-style centralized facilitators  
**Non-Goals:** Enforcing universal tolls, Preventing zero-cost resources, Token-specific minting  

---

> **This RFC defines HOW ACCESS BECOMES A DYNAMIC COVENANT.**  
> **Not through fixed barriers. Through velocity flows.**

---

> **Mauts filtern Parasiten; Discounts belohnen Produzenten.**  
> **Zahle blind; fließe frei.**

---

## 1. KONZEPT: DIE "DYNAMIC TOLL"

Statt fixer Gebühren nutzt Libertaria eine **Hamiltonian-gesteuerte Maut**, die mit System-Velocity ($V$) atmet.

| Velocity State | Toll Behavior | Economic Purpose |
|---------------|---------------|------------------|
| **V-High** (Überhitzung) | Tolls steigen exponentiell | Extraction-Vektor, um Momentum zu kühlen |
| **V-Low** (Stagnation) | Tolls sinken gegen Null | Stimulus, um Circulation zu fördern |
| **V-Normal** | Tolls = Base × Trust-Discount | Standard-Ressourcen-Allokation |

**Formel:**
```
Toll = Base × (1 + k·ε) × (1 - Discount)

where:
  ε = V_target - V_measured  (Velocity error from Hamiltonian)
  k = Scaling factor (RFC-0648 PID output)
  Discount = f(Rep_Score, Trust_Distance) [0.0 - 1.0]
```

Diese Dynamik verhindert Stagnation-Traps und Hyper-Erosion, wie in RFC-0648 definiert. Tolls sind nicht Strafen—sie sind der Preis der Ressourcen (Bandbreite, Storage, Compute), skaliert durch Trust und Rep.

---

## 2. ZK-STARK INTEGRATION (DIE PRIVACY-MAUT)

Um Tracking zu verhindern (wer zahlt was wann), integrieren wir **ZK-STARK #10: Toll Clearance Proof** (aus RFC-0130).

### 2.1 Der Prozess

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│   Router    │────▶│  Resource   │
└─────────────┘     └─────────────┘     └─────────────┘
       │                   │
       │ 1. Toll Required  │
       │◀──────────────────│
       │                   │
       │ 2. Generate       │
       │    Commitment     │
       │                   │
       │ 3. Pay → Pool     │
       │                   │
       │ 4. Generate       │
       │    STARK Proof    │
       │                   │
       │ 5. Toll Proof     │
       │──────────────────▶│
       │                   │
       │ 6. Verify STARK   │
       │    (Local)        │
       │                   │
       │ 7. Deliver        │
       │◀──────────────────│
```

### 2.2 STARK Circuit: TollClearanceCircuit

```rust
/// ZK-STARK #10: Toll Clearance Proof
struct TollClearanceCircuit {
    /// Public inputs
    commitment_hash: [u8; 32],      // Hash(Resource_ID || Amount || Nonce)
    toll_band: TollBand,             // Price range (for range proof)
    
    /// Private inputs (kept secret)
    resource_id: String,
    exact_amount: u64,
    nonce: [u8; 16],
    payment_receipt: PaymentReceipt,
}

impl TollClearanceCircuit {
    fn verify(&self) -> bool {
        // 1. Verify commitment matches hash
        let computed = blake3(&self.resource_id, 
                             &self.exact_amount.to_le_bytes(), 
                             &self.nonce);
        assert_eq!(computed, self.commitment_hash);
        
        // 2. Verify amount within toll band (range proof)
        assert!(self.exact_amount >= self.toll_band.min);
        assert!(self.exact_amount <= self.toll_band.max);
        
        // 3. Verify payment receipt
        self.payment_receipt.verify()
    }
}

struct TollClearanceProof {
    stark_proof: StarkProof,
    compressed: Option<CompressedProof>, // For Kenya
    commitment_hash: [u8; 32],
}
```

### 2.3 Kenya-Optimized Flow

```rust
fn generate_clearance_kenya(
    commitment: TollCommitment,
    payment_receipt: PaymentReceipt
) -> TollClearanceProof {
    let circuit = TollClearanceCircuit::new(commitment, payment_receipt);
    let proof = generate_stark(circuit);
    
    // Recursive compression for mobile/low-bandwidth
    proof.compress_for_mobile() // <5 KB
}

fn verify_lazy(
    proof: &TollClearanceProof,
    router: &RouterState
) -> VerificationResult {
    if router.is_resource_constrained() {
        // Commit now, verify later (batched)
        LazyVerification {
            commitment: proof.commitment_hash,
            deferred_until: Instant::now() + BATCH_WINDOW,
        }
    } else {
        // Verify immediately
        verify_stark(proof.stark_proof, proof.commitment_hash)
    }
}
```

### 2.4 Privacy-Garantien

| Leaked | Protected |
|--------|-----------|
| Commitment Hash (opaque) | Wallet Address |
| Toll Band (range) | Exact Amount Paid |
| Resource ID Hash | Specific Resource |
| Payment Occurred | Payment Method |
| Nullifier (anti-replay) | Payer Identity |

---

## 3. KENYA-SPECIFIC: "LEAN TOLLS"

Für low-resource Regionen (Kenya Rule): **Reputation-based Discounts**.

### 3.1 Discount-Formel

```rust
fn calculate_kenya_discount(
    rep_score: f64,
    trust_distance: u8,
    qvl_position: &TrustPosition,
) -> f64 {
    let rep_factor = (rep_score / REP_MAX).min(1.0);
    
    // Distance decay: closer = higher discount
    let distance_factor = match trust_distance {
        0 => 1.0,      // Self: full discount possible
        1 => 0.5,      // Friend: 50% cap
        2 => 0.25,     // FoF: 25% cap
        3 => 0.125,    // 12.5% cap
        _ => 0.0,      // Stranger: no discount
    };
    
    // Additional swarm bonus for high-rep nodes
    let swarm_bonus = if rep_score > SWARM_THRESHOLD {
        0.1 // Extra 10% for swarm guardians
    } else {
        0.0
    };
    
    (rep_factor * distance_factor + swarm_bonus).min(0.95) // Max 95% off
}
```

### 3.2 Anti-Gaming

| Attack | Mitigation |
|--------|------------|
| Fake Rep Scores | QVL STARK #4 (non-forgeable) |
| Discount Farming | Rep slashes on abuse (RFC-0121) |
| Sybil Networks | Larval Bootstrap (RFC-0250) |
| Ghost Tolls | Atomic nullifier invalidation (RFC-0205) |

---

## 4. DEPENDENCY INTEGRATION

### 4.1 RFC-0130 (ZK-STARK)

- **STARK #10:** TollClearanceCircuit (privacy-preserving payments)
- **STARK #4:** ReputationThreshold (for discount eligibility)
- **Recursive Compression:** Kenya compliance (<5KB proofs)

### 4.2 RFC-0205 (Passport)

```rust
impl ChapterPassport {
    /// Generate toll clearance without revealing identity
    fn prove_toll_clearance(
        &self,
        resource: ResourceId,
        toll_band: TollBand,
    ) -> TollClearanceProof {
        // Use cached STARK #4 for rep proof
        let rep_proof = self.cached_proofs.rep_threshold
            .expect("Rep proof required for tolls");
        
        // Generate toll-specific commitment
        let commitment = TollCommitment::new(
            resource,
            toll_band,
            self.soul_key.generate_nonce(),
        );
        
        self.proof_generator.generate(
            TollClearanceCircuit::new(commitment, rep_proof)
        )
    }
    
    /// Check if eligible for discount
    fn toll_discount_eligible(&self, &self) -> Option<DiscountProof> {
        if self.reputation.score < MIN_TOLL_REP {
            return None;
        }
        
        Some(self.proof_generator.generate(
            ReputationThresholdCircuit::new(
                MIN_TOLL_REP,
                self.reputation.score,
            )
        ))
    }
}
```

### 4.3 RFC-0648 (Hamiltonian)

```rust
/// Dynamic toll adjustment based on velocity
struct HamiltonianTollController {
    pid: PIDController,          // From RFC-0648
    base_toll: f64,
    velocity_window: Duration,
}

impl HamiltonianTollController {
    fn calculate_toll(
        &self,
        v_measured: f64,           // Current velocity
        v_target: f64,             // Target velocity
        discount: f64,             // From QVL/Rep
    ) -> TollAmount {
        let error = v_target - v_measured;
        let pid_output = self.pid.compute(error);
        
        // Scale base toll by PID output
        let adjusted = self.base_toll * (1.0 + pid_output);
        
        // Apply trust discount
        TollAmount {
            min: (adjusted * 0.9 * (1.0 - discount)) as u64,
            max: (adjusted * 1.1) as u64,
            target: (adjusted * (1.0 - discount)) as u64,
        }
    }
}
```

---

## 5. TOLL AGGREGATION (BOTTLENECK-BREAKER)

Router als Bottleneck? **Batch-Verification:**

```rust
/// Batch-Verify multiple tolls in one STARK
struct BatchTollCircuit {
    proofs: Vec<TollClearanceProof>,
}

impl BatchTollCircuit {
    fn verify_batch(&self,
        router: &mut RouterState
    ) -> BatchVerificationResult {
        // Collect all commitments
        let commitments: Vec<[u8; 32]> = self.proofs
            .iter()
            .map(|p| p.commitment_hash)
            .collect();
        
        // Single recursive STARK proving all proofs valid
        let batch_proof = generate_recursive_stark(
            &self.proofs
        );
        
        // Verify once, accept all
        if verify_stark(batch_proof, &commitments) {
            BatchVerificationResult::AllValid
        } else {
            // Fall back to individual verify
            self.verify_individually()
        }
    }
}

// Kenya: Lazy batch - commit now, verify later
struct LazyBatch {
    pending: Vec<PendingToll>,
    deadline: Instant,
}

impl LazyBatch {
    fn flush(&mut self,
        router: &mut RouterState
    ) -> Vec<TollClearanceProof> {
        if self.deadline <= Instant::now() 
            || self.pending.len() >= BATCH_SIZE {
            
            let batch = BatchTollCircuit::new(&self.pending
            );
            let result = batch.verify_batch(router);
            
            self.pending.clear();
            result
        } else {
            vec![] // Not yet
        }
    }
}
```

---

## 6. SECURITY CONSIDERATIONS

| Threat | Impact | Mitigation |
|--------|--------|------------|
| **Proof Forgery** | Free access | STARK soundness (collision-resistant) |
| **Discount Gaming** | Underpay via fake rep | QVL + STARK #4 (non-forgeable) |
| **Router Overhead** | DoS via verify flood | Batch + recursive compression |
| **Revocation Leak** | Ghost tolls | Atomic nullifier invalidation (RFC-0205) |
| **Replay Attack** | Double-spend | Nullifier cache + uniqueness proof |
| **Toll Evasion** | Bypass payment | Commitment binding + STARK verify |

---

## 7. IMPLEMENTATION NOTES

### 7.1 Wire Frame Integration (RFC-0000)

```rust
// New service types for tolls
const TOLL_REQUIRED: u16 = 0x0310;
const TOLL_PROOF: u16 = 0x0311;
const TOLL_RECEIPT: u16 = 0x0312;
const TOLL_BATCH: u16 = 0x0314;

/// L0 Wire Frame extension
struct TollRequiredFrame {
    resource_id: [u8; 32],
    toll_band: TollBand,           // Min/Max/Target
    accepted_methods: Vec<TollMethod>,
    velocity_context: VelocityReading, // For dynamic pricing
}

struct TollProofFrame {
    commitment: [u8; 32],
    stark_proof: CompressedProof,  // <5KB for Kenya
    nullifier: [u8; 32],           // Anti-replay
}
```

### 7.2 Membrane Agent Integration (RFC-0110)

```zig
// Zig implementation stub
pub const TollVerifier = struct {
    allocator: std.mem.Allocator,
    nonce_cache: NonceCache,
    batch_queue: LazyBatch,
    
    pub fn verifyToll(
        self: *TollVerifier,
        proof: TollClearanceProof,
        context: *const RouterContext,
    ) !bool {
        // 1. Check nullifier not spent
        if (self.nonce_cache.contains(proof.nullifier)) {
            return false; // Replay
        }
        
        // 2. Check commitment valid
        if (!verify_commitment(proof.commitment_hash)) {
            return false;
        }
        
        // 3. Route based on resources
        if (context.is_kenya_mode()) {
            // Lazy verification
            self.batch_queue.enqueue(proof);
            return true; // Optimistic
        } else {
            // Immediate verification
            return verify_stark(proof.stark_proof);
        }
    }
};
```

### 7.3 Passport Lifecycle Hooks

```rust
impl ChapterPassport {
    /// Called on revocation
    fn on_revoke(&mut self,
        reason: RevocationReason,
    ) {
        // Invalidate all pending toll nullifiers
        for nullifier in &self.pending_tolls {
            TOLL_REGISTRY.mark_spent(nullifier);
        }
        
        // Revoke rep-based discounts
        self.tbt_credential.is_active = false;
        
        // Atomic: All invalidations happen together
    }
}
```

---

## 8. COMPARISON: ATP vs x402

| Dimension | x402 | ATP (RFC-0315) |
|-----------|------|----------------|
| **Facilitator** | Coinbase (centralized) | None (local STARK verify) |
| **Payment types** | USDC only (EIP-3009) | Entropy, Rep, Token, Energy, Lightning |
| **Pricing** | Uniform per-endpoint | Trust-scaled + Hamiltonian-dynamic |
| **Gas cost** | Chain write per payment | **Zero** (proof is self-validating) |
| **Privacy** | None (transparent) | **Full** (ZK-STARK hiding) |
| **Offline support** | None | Full (entropy + lazy batch) |
| **Kenya compliance** | None | Native |
| **Smart contract hooks** | None | Native (extension fields) |

---

## 9. REFERENCES

| RFC | Title | Relationship |
|-----|-------|--------------|
| RFC-0130 | ZK-STARK Primitive Layer | Privacy proofs, recursive compression |
| RFC-0205 | ChapterPassport Protocol | Credential lifecycle, nullifier management |
| RFC-0648 | Hamiltonian Economic Dynamics | Velocity-based toll scaling |
| RFC-0000 | Wire Frame | L0 transport for toll frames |
| RFC-0010 | UTCP | Connection-level toll integration |
| RFC-0120 | QVL | Trust distance for discounts |
| RFC-0121 | Slash Protocol | Rep punishment for toll gaming |
| RFC-0630 | TBT | Reputation-based payment method |
| RFC-0641 | Energy Token | Energy-based payment method |

---

## 10. CHANGELOG

### v0.3.0 (2026-02-05)
- ZK-STARK integration (RFC-0130)
- Hamiltonian velocity coupling (RFC-0648)
- Passport lifecycle hooks (RFC-0205)
- Kenya-specific optimizations
- Toll aggregation for routers

### v0.2.0 (2026-02-04)
- Gas-less guarantee specified
- Multi-modal payment registry
- Smart contract hooks
- Agent delegation framework

### v0.1.0 (2026-02-03)
- Initial concept
- Trust-scaled pricing
- Comparison with x402

---

## 11. CLOSING PRINCIPLES

> **Gas is friction. Proof is flow.**  
> **The toll is not a gate; it is a handshake.**  
> **Strangers prove with entropy. Kin prove with scars.**  > **ZK conceals; STARK verifies; Hamiltonian breathes.**  > **x402 asks: "Do you have money?"**  > **ATP asks: "Do you have value?"**  > **Value is time. Value is trust. Value is work. Value is standing.**  > **The Protocol accepts all. The Protocol charges none.**  > **Zahle blind; fließe frei.**

---

**END RFC-0315 v0.3.0**
