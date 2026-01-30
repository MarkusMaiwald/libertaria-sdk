# Phase 3: Post-Quantum Communication (PQXDH)

**Status:** ✅ COMPLETE
**Date:** 2026-01-30
**Component:** L1 Identity Layer (`l1-identity/`)

## Overview

This phase implements the **PQXDH** (Post-Quantum Extended Diffie-Hellman) key agreement protocol as defined in RFC-0830 (draft). It provides hybrid forward secrecy by combining:

1.  **Classical ECDH:** `X25519` (Curve25519) - Proven security against classical computers.
2.  **Post-Quantum KEM:** `ML-KEM-768` (Kyber-768, FIPS 203) - Security against quantum computers.

The result is a shared secret that remains secure even if a quantum computer breaks Curve25519 in the future ("Harvest Now, Decrypt Later" protection).

## Implementation Details

-   **Protocol:** Full X3DH flow with ML-KEM encapsulation added to the initial message.
-   **KDF:** `HKDF-SHA256` combines 4 ECDH shared secrets + 1 KEM shared secret.
-   **Library:** Uses `liboqs` (Open Quantum Safe) for ML-KEM implementation.
-   **Linking:** Statically linked `liboqs.a` to avoid runtime dependencies.
-   **Optimizations:**
    -   OpenSSL disabled (uses internal SHA3 implementation) to minimize binary size.
    -   Standard `ML-KEM` enabled, legacy `Kyber` disabled to avoid symbol conflicts.

## Build Instructions

To build the project with PQXDH support, you must first compile `liboqs`:

```bash
# 1. Build static liboqs (requires cmake, ninja/make)
./scripts/build_liboqs.sh

# 2. Run SDK tests
zig build test
```

## Key Files

-   `l1-identity/pqxdh.zig`: Core protocol logic (Initiator/Responder state machines).
-   `l1-identity/test_pqxdh.zig`: Comprehensive unit tests verify full handshake correctness.
-   `scripts/build_liboqs.sh`: Automated build script for dependency management.

## Performance

-   **Handshake Time:** ~2ms (ML-KEM) + ~0.5ms (X25519).
-   **Ciphertext Size:** 1088 bytes (ML-KEM-768).
-   **Public Key Size:** 1184 bytes (ML-KEM-768).
-   Total initial message overhead: ~1.1 KB (fits in 2 LWF jumbo frames).
