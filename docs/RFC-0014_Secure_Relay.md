# RFC-0014: Secure Relay Protocol

## Overview
The Secure Relay Protocol (Layer 2) enables private, onion-routed communication within the Libertaria network. It upgrades the transport layer with privacy-preserving encryption, forward secrecy, and session binding.

## 1. Cryptographic Primitive
- **Encryption:** `XChaCha20-Poly1305` (Authenticated Encryption with Associated Data).
- **Key Exchange:** `X25519` (Elliptic Curve Diffie-Hellman) for ephemeral shared secrets.
- **Forward Secrecy:** Yes. Each circuit uses ephemeral keys.

## 2. Session Binding & Usage

### 2.1 The "Sticky" Session
To balance privacy with network health (spam protection), sessions are **pseudo-anonymous but stable**.
- **Session ID:** 16 bytes. Generated randomly by the **Client** (Initiator).
- **Stickiness:** Packets within a context flow re-use the Session ID.
- **Privacy:** Routers see only the Session ID (for rate-limiting) but cannot correlate it to a user Identity (DID) without owning the private key.

### 2.2 Nonce Construction
Strict binding of Session ID to the Encryption Nonce prevents replay and context-confusion attacks.
**Warning:** The protocol **REJECTS** any packet where the nonce does not match the session.

**Nonce Format (24 bytes):**
```
| Session ID (16 bytes) | Counter/Random (8 bytes) |
```
- **Byte 0-15:** MUST match the declared Session ID.
- **Byte 16-23:** Monotonically increasing counter or random salt (Client controlled).

### 2.3 Key Management
- **Relay Keys:** Public X25519 keys are distributed via the DHT/Federation (`dht_nodes` message).
- **Circuit Keys:** Ephemeral keys are generated per circuit (or per packet in stateless mode).
- **Optimization:** Sticky Sessions allow reusing the Ephemeral Key Pair for multiple packets, reducing ECDH overhead for high-throughput flows.

## 3. Wire Format (RelayPacket)
```zig
struct RelayPacket {
    ephemeral_key: [32]u8, // Network Byte Order
    nonce:         [24]u8, // [SessionID (16) | Rand (8)]
    ciphertext:    []u8,   // Encrypted [NextHop + Payload]
}
```

## 4. Privacy Considerations
- **Timestamp Leakage:** The protocol deliberately **excludes** unencrypted timestamps in the header to prevent traffic correlation attacks.
- **Client Sovereignty:** The Client generates the Session ID. Bridges/Guards cannot force a tracking ID onto the client.
- **Verification:** Relays verify the Tag (Poly1305) and Session Binding before forwarding.

