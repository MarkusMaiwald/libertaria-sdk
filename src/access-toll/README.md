# RFC-0315 Access Toll Protocol - Zig Verifier PoC

**Status:** IMPLEMENTATION v0.1.0  
**Target:** Zig 0.13+  
**License:** EUPL-1.2

## Overview

This is a Proof-of-Concept implementation of the **Privacy-Preserving Access Toll** verifier from RFC-0315. It demonstrates:

- **ZK-STARK Toll Clearance Proofs** (structure only - production uses winterfell/starky)
- **Lazy Batch Verification** for Kenya compliance
- **Nullifier-based Replay Prevention**
- **Trust-Scaled Toll Bands**

## Structure

```
access-toll/
├── toll_verifier.zig    # Main implementation
├── build.zig            # Build configuration
└── README.md            # This file
```

## Core Components

### TollClearanceProof
ZK-STARK #10 proof structure containing:
- `stark_proof`: FRI-based STARK (placeholder in PoC)
- `compressed`: Recursive compression for Kenya mode (<5KB)
- `commitment_hash`: Opaque toll commitment (blake3)
- `nullifier`: Anti-replay nonce
- `toll_band`: Acceptable price range

### TollVerifier
Main verification engine:
- **Immediate mode**: Full STARK verification (high-resource routers)
- **Lazy mode**: Optimistic acceptance with batch verification (Kenya mode)
- **Replay prevention**: Nullifier cache with GC

### LazyBatch
Resource-constrained verification queue:
- Accumulates proofs for batch processing
- Time and size-based flush triggers
- Recursive STARK aggregation (placeholder in PoC)

## Build & Run

```bash
# Build library
zig build

# Run demo
zig build run

# Run tests
zig build test
```

## Demo Output

```
=== RFC-0315 Toll Verifier PoC ===

[1] Verifier initialized
[2] Commitment computed: a1b2c3d4...
[3] Immediate verification: valid

[4] Kenya Mode (lazy batching):
    Toll 1: valid (queued)
    Toll 2: valid (queued)
    ...
[5] Batch processed

[Stats] Verified: 11, Rejected: 0
```

## Integration Points

### RFC-0130 (ZK-STARK)
Replace placeholder `verifyStarkImmediate()` with actual winterfell/starky verification:

```zig
// Production integration
const winterfell = @import("winterfell");

fn verifyStarkImmediate(proof: StarkProof) !bool {
    return winterfell.verify(
        proof.data,
        TollClearanceAir{},  // Constraint system
        proof.public_inputs,
    );
}
```

### RFC-0205 (Passport)
Nullifiers are derived from Passport soul keys:

```zig
const nullifier = Nullifier.fromCommitment(
    commitment,
    passport.soul_key,
);
```

### RFC-0648 (Hamiltonian)
Toll bands are adjusted by PID controller output:

```zig
const adjusted_band = hamiltonian.scaleTollBand(
    base_band,
    velocity_error,
);
```

## Testing

Run all tests:
```bash
zig build test
```

Tests cover:
- Toll band range checking
- Commitment determinism
- Replay prevention
- Immediate vs lazy verification
- Batch queue mechanics

## Kenya Compliance

The implementation supports "Lean Tolls" for low-resource environments:

1. **Compressed proofs**: <5KB recursive STARKs
2. **Lazy verification**: Accept first, verify in batch
3. **Memory efficient**: Bounded nullifier cache with GC
4. **Bandwidth optimized**: Batch multiple tolls in one verification

## Next Steps

- [ ] Integrate winterfell for real STARK verification
- [ ] Add recursive proof compression
- [ ] Implement QVL trust-scaled discounts
- [ ] Hamiltonian velocity coupling
- [ ] Wire Frame L0 transport integration

## References

- RFC-0315: Privacy-Preserving Access Tolls
- RFC-0130: ZK-STARK Primitive Layer
- RFC-0205: ChapterPassport Protocol
- RFC-0648: Hamiltonian Economic Dynamics
