# RFC-0315 Access Toll Protocol - Winterfell Edition

**Status:** WINTERFELL INTEGRATION v0.2.0  
**Target:** Zig 0.13+ + Winterfell (Rust STARK library)  
**License:** EUPL-1.2

## Strategic Decision: Winterfell over Cairo

| Dimension | Winterfell | Cairo VM |
|-----------|------------|----------|
| **Modularity** | ✅ Clean prover/verifier separation | ❌ Monolithic VM |
| **Integration** | ✅ C FFI → easy Zig bindings | ❌ VM embedding complexity |
| **Stack Size** | ✅ ~5KB recursive proofs | ❌ Larger proof overhead |
| **Libertaria Fit** | ✅ Matches minimal philosophy | ❌ Overkill for our needs |
| **Compile Time** | ✅ Fast Rust compilation | ❌ Slow VM initialization |

**Winner:** Winterfell for clean, modular STARK integration into Membrane.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     MEMBRANE AGENT                          │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │  Toll Band  │───▶│   Winterfell │───▶│  STARK Proof    │ │
│  │  (Hamilton) │    │   Prover    │    │  (Serialized)   │ │
│  └─────────────┘    └─────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Network (zero-knowledge)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      ROUTER NODE                            │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐ │
│  │  Hamilton   │◀───│   Winterfell │───▶│  Resource       │ │
│  │  Controller │    │   Verifier   │    │  Access         │ │
│  └─────────────┘    └─────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Files

```
access-toll/
├── toll_verifier_winterfell.zig    # Main implementation (Winterfell FFI)
├── toll_verifier.zig               # Legacy PoC (placeholder STARKs)
├── build.zig                       # Build configuration
└── README.md                       # This file
```

## Core Components

### 1. Hamiltonian Toll Controller (`HamiltonianToll`)

Integrates RFC-0648 velocity-based pricing:

```zig
var ham = HamiltonianToll{
    .pid = PidController.init(0.5, 0.1, 0.05),
    .base_toll = 250,
    .v_target = 1.0,
};

const band = ham.calculate(v_measured, dt);
// V < target → reduced toll (stimulus)
// V > target → increased toll (cooling)
```

### 2. Winterfell STARK Circuit (`TollAir`)

AIR (Algebraic Intermediate Representation) for toll clearance:

```zig
const TollAir = extern struct {
    trace_width: u32,          // 5 columns
    trace_length: u32,         // 64 rows (power of 2)
    constraint_degrees: ...,   // Quadratic constraints
    public_inputs: ...,        // commitment_hash, nullifier
    assertions: ...,           // Boundary constraints
};
```

**Trace Layout:**
| Column | Purpose |
|--------|---------|
| 0 | Resource ID hash (Blake3 intermediate) |
| 1 | Amount (decomposed for range check) |
| 2 | Nonce |
| 3 | Commitment computation trace |
| 4 | Nullifier derivation |

### 3. Proof Generation (`generateTollProof`)

```zig
const proof = try generateTollProof(
    allocator,
    resource_id,
    amount,
    nonce,
    secret_key,
    toll_band,
);

// Returns TollClearanceProof with:
// - stark_proof: Winterfell STARK
// - serialized: Bytes for transmission
// - commitment_hash, nullifier: Public inputs
```

### 4. Kenya-Optimized Verification

**Immediate Mode** (high-resource routers):
- Full Winterfell verification
- ~10-50ms verification time

**Lazy Mode** (Kenya/low-resource):
- Optimistic acceptance
- Batch verification (100 proofs)
- Recursive compression (<5KB)

```zig
if (context.shouldLazyVerify()) {
    // Queue for batch
    try batch_queue.enqueue(proof);
    return .valid; // Optimistic
} else {
    // Immediate verification
    return winterfell_verify(...);
}
```

## Build Instructions

### Prerequisites

```bash
# 1. Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# 2. Clone Winterfell
git clone https://github.com/novifinancial/winterfell.git
cd winterfell

# 3. Build with C FFI
cargo build --release --features ffi
```

### Zig Build

```bash
cd src/access-toll

# Link with Winterfell
zig build-exe toll_verifier_winterfell.zig \
    -lwinterfell_ffi \
    -L/path/to/winterfell/target/release

# Run tests
zig test toll_verifier_winterfell.zig \
    -lwinterfell_ffi \
    -L/path/to/winterfell/target/release
```

## Integration Points

### RFC-0130 (ZK-STARK)
- **STARK #10**: TollClearanceCircuit (this implementation)
- **Recursive Compression**: Kenya mode (<5KB)
- **Proof Options**: Optimized for mobile (80 queries, 4x blowup)

### RFC-0205 (Passport)
```zig
// Nullifier derived from Passport soul key
const nullifier = Nullifier.derive(commitment, passport.soul_key);
```

### RFC-0648 (Hamiltonian)
```zig
// Dynamic toll adjustment
const band = hamiltonian.calculate(v_measured, dt);
assert(band.contains(proof.toll_band.target));
```

### Membrane Agent Runtime
```zig
// Agent pays toll before resource access
const proof = try generateTollProof(...);
const result = try router.verifyToll(proof, context, v_measured);
```

## Privacy Guarantees

| Leaked | Protected |
|--------|-----------|
| Commitment Hash (opaque) | Wallet Address |
| Toll Band (range) | Exact Amount |
| Nullifier (anti-replay) | Payer Identity |
| Payment Occurred | Payment Method |

**STARK Properties:**
- Zero-knowledge: Verifier learns nothing beyond validity
- Succinct: ~5KB proofs (Kenya recursive)
- Transparent: No trusted setup

## Performance

| Metric | Target | Notes |
|--------|--------|-------|
| Proof Size | 5-10 KB | Raw STARK |
| Recursive Size | <5 KB | Kenya compression |
| Proof Time | 1-5s | Client-side |
| Verify Time | 10-50ms | Router-side |
| Batch Verify | 100 proofs/200ms | Lazy mode |

## Next Steps

- [ ] Winterfell FFI bindings (actual C ABI)
- [ ] Recursive compression (FRI folding)
- [ ] QVL trust-scaled discounts
- [ ] Membrane L1 integration
- [ ] Router load testing

## References

- RFC-0315: Privacy-Preserving Access Tolls
- RFC-0130: ZK-STARK Primitive Layer
- RFC-0205: ChapterPassport Protocol
- RFC-0648: Hamiltonian Economic Dynamics
- [Winterfell](https://github.com/novifinancial/winterfell): STARK prover/verifier in Rust

---

> *"Die Maut ist nicht das Ziel; sie ist der Filter, der die Parasiten von den Produzenten trennt."* 🗡
