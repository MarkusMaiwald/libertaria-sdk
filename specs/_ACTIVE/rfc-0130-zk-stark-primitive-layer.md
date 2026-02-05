# RFC-0130: ZK-STARK Primitive Layer

**Status:** DRAFT  
**Version:** 0.1.0  
**Layer:** L1.5 (Identity & Privacy Substrate)  
**Class:** FOUNDATIONAL / PRIVACY  
**Author:** Markus Maiwald  
**Date:** 2026-02-04  
**Depends On:** RFC-0120 (QVL), RFC-0250 (Larval Identity), RFC-0648 (Hamiltonian Dynamics)  
**Related:** RFC-0121 (Slash Protocol), RFC-0315 (Access Toll Protocol), RFC-0205 (ChapterPassport)  
**Supersedes:** Trusted-setup ZK (SNARKs), Non-post-quantum proofs  

---

> **This RFC defines HOW PROOFS PRESERVE PRIVACY WITHOUT POWER.**  
> **Not through trust. Through transparency.**

---

> **Kein Setup, kein Gott—nur Mathe.**

---

## 1. ABSTRACT

Libertaria demands proofs of properties (reputation, balance, membership) without leaking underlying data. RFC-0130 specifies ZK-STARK integration: Zero-Knowledge Scalable Transparent Arguments of Knowledge.

**STARKs chosen over SNARKs:**
- No trusted setup (no toxic waste)
- Post-quantum resistant
- Fully transparent

**Kenya Compliance:** Recursive compression—reducing proofs from 45-200 KB to 2-5 KB.

---

## 2. STARK VS SNARK DECISION

| Criterion | ZK-SNARK | ZK-STARK |
|-----------|----------|----------|
| **Trusted Setup** | Yes (toxic waste risk) | No (transparent) |
| **Post-Quantum** | No | Yes |
| **Proof Size** | ~200 bytes | ~45-200 KB (compressible) |
| **Verification** | O(1) fast | O(log n) |
| **Prover Cost** | Medium | High (but parallelizable) |
| **Kenya Fit** | ✓ (small) | △ (large; compress) |

**Verdict:** STARKs for Libertaria: No hidden power, future-proof.

---

## 3. THE STARK CIRCUITS

### 3.1 MembershipCircuit
- **Purpose:** Proves membership in Merkle tree without revealing index
- **Util:** Anonymous voting, mint-window admission
- **Logic:** `verify_membership(root, nullifier, proof)`

### 3.2 ReputationThresholdCircuit
- **Purpose:** Proves rep ≥ X without exact score
- **Util:** Chapter passports, access to protected channels
- **Logic:** `verify_range(public_threshold, private_rep, proof)`

### 3.3 TrustDistanceCircuit
- **Purpose:** Proves path length ≤ d in QVL graph
- **Util:** Slashing rights, trust-level transactions
- **Logic:** `verify_distance(target_node, max_dist, private_path, proof)`

### 3.4 BalanceRangeCircuit
- **Purpose:** Proves balance in [min, max]
- **Util:** Creditworthiness without wealth leak

### 3.5 VelocityContributionCircuit
- **Purpose:** Proves ≥ X transactions in epoch
- **Util:** Hamiltonian velocity measurement (RFC-0648)

### 3.6 DelegationChainCircuit
- **Purpose:** Proves valid delegation chain
- **Util:** Anonymous voting (RFC-0310)

---

## 4. KENYA COMPLIANCE: RECURSIVE COMPRESSION

**Problem:** STARK proofs 45-200 KB
**Solution:** Proof-of-Proof (PoP)

```rust
struct LibertariaProof {
    stark_proof: StarkProof,
    compressed: Option<CompressedProof>,  // ~2-5 KB
    vk_commitment: [u8; 32],
}

impl LibertariaProof {
    fn compress_for_mobile(&self) -> CompressedProof {
        // Recursive STARK: Proof over proof
        let circuit = RecursiveVerificationCircuit::new(&self.stark_proof
        );
        generate_stark(circuit)  // 2-5 KB result
    }
    
    fn verify_lazy(&self, vk: &VerificationKey
    ) -> LazyVerification {
        // For resource-constrained: commit now, verify later
        LazyVerification {
            commitment: self.vk_commitment,
            deferred_until: Instant::now() + GRACE_PERIOD,
        }
    }
}
```

---

## 5. DID/VC INTEGRATION

**W3C Verifiable Credentials format:**

```json
{
  "@context": ["https://www.w3.org/2018/credentials/v1"],
  "type": ["VerifiableCredential", "LibertariaMembership"],
  "issuer": "did:lib:chapter123",
  "credentialSubject": {
    "id": "did:lib:user456",
    "isMember": true
  },
  "proof": {
    "type": "StarkProof2026",
    "proofValue": "compressed_stark_bytes",
    "verificationMethod": "did:lib:verifier789"
  }
}
```

---

## 6. ZK-STARK MAP

| Use Case | Layer | Circuit | Purpose |
|----------|-------|---------|---------|
| SoulKey Existence | L1 | MembershipCircuit | Anonymous identity |
| Larval Bootstrap | L1 | MembershipCircuit | Sybil resistance |
| Trust Distance | L1 QVL | TrustDistanceCircuit | Submarine doctrine |
| Reputation Threshold | L1 QVL | ReputationThresholdCircuit | Access control |
| Balance Range | L2 Econ | BalanceRangeCircuit | Credit privacy |
| Velocity Contribution | L2 Econ | VelocityContributionCircuit | Hamiltonian proof |
| Voting Eligibility | L2 Gov | MembershipCircuit | Anonymous voting |
| Delegation Chain | L2 Gov | DelegationChainCircuit | Liquid democracy |
| Chapter Membership | L3 Fed | MembershipCircuit | Cross-chapter |

---

## 7. CLOSING PRINCIPLES

> **Proofs without power; privacy without permission.**  > **STARKs: Mathe als Schild, nicht als Schwert.**  > **Kein Setup, kein Leak—nur Souveränität.**

---

**END RFC-0130 v0.1.0**
