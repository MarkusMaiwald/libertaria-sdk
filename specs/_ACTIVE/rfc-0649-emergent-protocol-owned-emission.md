# RFC-0649: Emergent Protocol-Owned Emission (EPOE)

**Status:** DRAFT  
**Category:** L1 Monetary Mechanics  
**Author:** Markus Maiwald  
**Co-Author:** Claude (Anthropic)  
**Date:** 2026-02-04  
**Depends On:** RFC-0648 (Hamiltonian Dynamics), RFC-0630 (TBT), RFC-0100 (Entropy)  
**Supersedes:** Validator-based minting, Universal Basic Income, Pure laissez-faire

---

## 0. OPENING AXIOM

> **Money is not gifted. Money is earned through work.**  
> **But the system can make work cheaper and more rewarding when stimulus is needed.**  
>  
> **This is not Universal Dividend (welfare).**  > **This is Opportunity Window (infrastructure).**

---

## 1. THE SYNTHESIS

Combining the best of three approaches:

| Source | Contribution |
|--------|--------------|
| **Ansatz 1** (Passive) | Argon2d simplicity; no validators |
| **Ansatz 2** (POE) | PID Enshrined; Base Fee Burn |
| **Ansatz 3** (Swarm) | Emergence philosophy; Multi-Token |

**Result:** Emergent Protocol-Owned Emission (EPOE)

---

## 2. THE FOUR PILLARS

### 2.1 Pillar I: Injection (Opportunity Windows)

**When:** V < V_target (Stagnation)  
**Mechanism:**
```rust
fn on_velocity_drop(state: &mut State) {
    // Difficulty drop = cheaper to mint
    state.argon2d_difficulty *= 0.9;
    
    // Opportunity Multiplier = more rewarding
    state.mint_multiplier = 1.5;  // 50% bonus
    
    // Time-limited window
    state.mint_window_expires = now() + 24h;
}
```

**Key Insight:**
- NOT: "Here is free money" (Universal Dividend)
- BUT: "Work is now cheaper AND more rewarding"
- WHO MINTS: Anyone with valid SoulKey
- COST: Argon2d proof (real work, not free)

**Radical Left Capitalism:**
> The market regulates, but the rules are set so stagnation automatically opens opportunities for the base.

---

### 2.2 Pillar II: Extraction (Double Brake)

**When:** V > V_target (Overheating)  
**Mechanism:**
```rust
fn on_velocity_spike(state: &mut State) {
    // Active transactors pay
    state.base_fee *= 1.1;  // EIP-1559 style burn
    
    // Passive hoarders pay
    state.demurrage_rate = 0.001;  // 0.1% per epoch
}
```

**Double Pressure:**
1. **Transactions** = more expensive (Base Fee)
2. **Hoarding** = costly (Demurrage on stagnant tokens)

**Result:** Money MUST move or it decays.

---

### 2.3 Pillar III: Anti-Sybil (Larval Bootstrap)

**Genesis (One-time):**
```rust
struct SoulKey {
    genesis_entropy: EntropyStamp,  // Argon2d proof
    created_at: Epoch,
}
```
- Cost: ~1 minute of CPU
- Prevents spam account creation

**Maintenance (Continuous):**
```rust
fn qualify_for_mint_window(soul: &SoulKey) -> bool {
    // Must have genesis
    if soul.genesis_entropy.is_none() { return false; }
    
    // Must be maintained
    if soul.maintenance_debt > THRESHOLD { return false; }
    
    // Kenya Rule: 1 proof per month
    // Tragbar on mobile phone
    true
}
```
- Cost: ~10 seconds of CPU per month
- Prevents "sleeper armies"

**No Identity Oracle needed.** Proof-of-work IS the identity.

---

### 2.4 Pillar IV: Controller (Enshrined PID)

**Hard Protocol Caps (Immutable):**
```rust
const PROTOCOL_FLOOR: f64 = -0.05;    // Max 5% deflation
const PROTOCOL_CEILING: f64 = 0.20;   // Max 20% inflation
```

**Chapter Sovereignty (Tunable):**
```rust
fn compute_delta_m(chapter: &Chapter, velocity: f64) -> f64 {
    let epsilon = chapter.v_target - velocity;
    
    // Chapter tunes their own PID
    let raw = chapter.k_p * epsilon 
            + chapter.k_i * integral(epsilon) 
            + chapter.k_d * derivative(epsilon);
    
    // But protocol caps are ABSOLUTE
    clamp(raw, PROTOCOL_FLOOR, PROTOCOL_CEILING)
}
```

**Enshrined:**
- No admin key
- No DAO override  
- Math only
- Caps in L1 kernel

---

## 3. ARCHITECTURE

```
┌──────────────────────────────────────────────────────────────┐
│ HAMILTONIAN CORE (L1)                                        │
│ ──────────────────────────────────────────────────────────── │
│ PID Controller (Enshrined, Caps: -5%/+20%)                   │
│ Velocity Measurement (QVL Transaction Graph)                 │
│ NO ADMIN KEY. NO DAO OVERRIDE. MATH ONLY.                  │
└──────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┴───────────────┐
          ▼                                   ▼
┌─────────────────────────┐    ┌─────────────────────────┐
│ INJECTION (V < target) │    │ EXTRACTION (V > target) │
│ ─────────────────────── │    │ ─────────────────────── │
│ • Difficulty ↓          │    │ • Base Fee ↑ (Burn)     │
│ • Mint Window Opens     │    │ • Demurrage Activates   │
│ • Multiplier Bonus      │    │ • High-V Actors Pay     │
│ ─────────────────────── │    │ ─────────────────────── │
│ WHO MINTS: Anyone with  │    │ WHO PAYS: Transactors   │
│ valid SoulKey           │    │ + Hoarders              │
│ (Genesis + Maintenance) │    │                         │
└─────────────────────────┘    └─────────────────────────┘
```

---

## 4. KENYA COMPLIANCE

| Constraint | EPOE Solution |
|------------|---------------|
| No wallet | Argon2d = wallet (CPU only) |
| No internet | OPQ queuing for mint proofs |
| Solar dropout | Maintenance debt accumulates gracefully |
| Feature phone | 10-second Argon2d possible on low-end |
| No KYC | Proof-of-work IS identity |

---

## 5. COMPARISON

| Kriterium | Ansatz 1 | Ansatz 2 | Ansatz 3 | **EPOE (Synthese)** |
|-----------|----------|----------|----------|---------------------|
| Anti-Plutokratie | ✓ | ✓ | ✓ | ✓ |
| Aktive Intervention | ✗ | ✓ | △ | ✓ |
| Philosophische Reinheit | ✓ | △ | ✓ | ✓ |
| Implementierbarkeit | ✓ | ✓ | △ | ✓ |
| Kenya Compliance | ✓ | △ | ✓ | ✓ |
| Sybil Resistance | △ | ✓ | ✓ | ✓ |
| **Gesamt** | 6/10 | 7/10 | 8/10 | **9/10** |

---

## 6. CLOSING AXIOM

> **Not Universal Dividend.**  
> **Not Validator Plutocracy.**  > **Not Passive Chaos.**  >  > **Opportunity Windows.**  > **Work is always required.**  > **But the system can make work worthwhile.**  >  > **Radical Left Capitalism:**  > **The market serves the base.**

---

**END RFC-0649 v0.1.0**

> *"The best welfare is a job. The best stimulus is opportunity."*
