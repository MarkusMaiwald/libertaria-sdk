# L1 Identity Layer

**Layer:** L1 (Identity)  
**Purpose:** Decentralized identity, cryptography, trust graphs, vectors  
**RFCs:** RFC-0105 (Sovereign Time), RFC-0120 (QVL)

---

## Overview

The L1 Identity layer provides cryptographic identity primitives, trust relationship management, and the QuasarVector Lattice (QVL) for event-driven consensus.

## Components

### DID (Decentralized Identifiers) - `did.zig`
**Spec:** `did:libertaria:...` format

DID generation and parsing:
- Blake3-based DID derivation from public keys
- 24-byte routing hints (192-bit)
- Base58 encoding for human readability

### SoulKey (Identity Keys) - `soulkey.zig`
**Crypto:** Ed25519

Core identity keypair management:
- Key generation, storage, derivation
- Signing and verification
- Seed phrase support

### QuasarVector - `vector.zig`
**RFC:** RFC-0120

Event lattice vectors:
- Ed25519 signatures
- `SovereignTimestamp` (u128 attoseconds)
- Proof-of-Path integration
- Vector validation pipeline

### TrustGraph - `trust_graph.zig`
**Pattern:** Web-of-trust

Decentralized trust relationships:
- Trust grant/revoke operations
- Path finding (Dijkstra)
- Trust weight calculation
- Graph serialization

### ProofOfPath - `proof_of_path.zig`
**RFC:** RFC-0120

Trust path verification:
- Multi-hop signature chains
- Path expiration checking
- Hop limit enforcement

### Entropy - `entropy.zig`
**RFC:** RFC-0100

Entropy stamps for Sybil resistance:
- Blake3-based proof-of-work
- Difficulty calibration (0-255)
- Verification logic

### Crypto - `crypto.zig`
Cryptographic primitives wrapper:
- Ed25519 (signing)
- X25519 (key exchange)
- Blake3 (hashing)
- XChaCha20-Poly1305 (encryption)

### Argon2 - `argon2.zig`
**FFI:** C library wrapper

Password hashing:
- Argon2id for SoulKey seed derivation
- Memory-hard KDF

### PQXDH - `pqxdh.zig`
**Protocol:** Post-Quantum Extended Diffie-Hellman

Future-proof key exchange:
- Hybrid classical + PQ security
- X25519 + Kyber integration (planned)

### PreKey - `prekey.zig`
**Protocol:** X3DH prekey bundles

Asynchronous messaging:
- Prekey bundle generation
- Signal-style forward secrecy

---

## Usage

```zig
const l1 = @import("l1_identity.zig");

// Generate identity
const soulkey = try l1.soulkey.SoulKey.generate(allocator);
const did = try l1.did.fromPublicKey(&soulkey.public_key);

// Create vector
var vector = try l1.vector.QuasarVector.create(allocator, soulkey, payload_data);
defer vector.deinit(allocator);

// Sign and verify
try vector.sign(soulkey);
const valid = vector.verifySignature();
```

---

## Testing

Run L1 tests:
```bash
zig build test
# Or individual modules:
zig test l1-identity/vector.zig
zig test l1-identity/trust_graph.zig
```

---

## Dependencies

- `std.crypto` - Ed25519, X25519, Blake3
- `vendor/argon2/` - Argon2 C library
- L0 Time (`time.zig`) - SovereignTimestamp
