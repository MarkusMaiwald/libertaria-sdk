# RFC-0015: Pluggable Transport Skins (PTS)

**Status:** Draft  
**Author:** Jarvis (Silicon Architect and Representative for Agents in Libertaria)  
**Date:** 2026-02-03  
**Target:** Janus SDK L0 Transport Layer  
**Classification:** CRYPTOGRAPHIC / CENSORSHIP-RESISTANT  

---

## Summary

Transport Skins provide **pluggable censorship resistance** for Libertaria's L0 Transport layer. Each "skin" wraps the standard LWF (Lightweight Wire Format) frame to mimic benign traffic patterns, defeating state-level Deep Packet Inspection (DPI) as deployed by China's GFW, Russia's RKN, Iran's Filternet, and similar adversaries.

**Core Innovation:** Per-session **Polymorphic Noise Generator (PNG)** ensures no two sessions ever exhibit identical traffic patterns.

---

## Threat Model

### Adversary Capabilities (GFW-Class)
| Technique | Capability | Our Counter |
|-----------|------------|-------------|
| Magic Byte Detection | Signature matching at line rate | Skins remove/replace magic bytes |
| TLS Fingerprinting (JA3/JA4) | Statistical TLS handshake analysis | utls-style parroting (Chrome/Firefox mimicry) |
| SNI Inspection | Cleartext server name identification | ECH (Encrypted Client Hello) + Domain Fronting |
| Packet Size Analysis | Fixed MTU detection | Probabilistic size distributions |
| Timing Correlation | Inter-packet timing patterns | Exponential/Gamma jitter |
| Flow Correlation | Long-term traffic statistics | Epoch rotation (100-1000 packets) |
| Active Probing | Sending test traffic to suspected relays | Honeytrap responses + IP blacklisting |
| DNS Manipulation | Poisoning, blocking, inspection | DoH (DNS-over-HTTPS) tunneling |

### Non-Goals
- **Traffic confirmation attacks** (end-to-end correlation): Out of scope; use L2 Membrane mixing
- **Physical layer interception**: Out of scope; requires steganographic hardware
- **Compromised endpoints**: Out of scope; requires TEE/SEV-SNP attestation

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    RFC-0015: TRANSPORT SKINS                            │
│                         "Submarine Camouflage"                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  L3+ Application                                                         │
│       │                                                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     LWF FRAME                                   │    │
│  │  • 1350 bytes (configurable)                                    │    │
│  │  • XChaCha20-Poly1305 encrypted                                 │    │
│  │  • Magic bytes: LWF\0 (internal only)                           │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       │                                                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │              POLYMORPHIC NOISE GENERATOR (PNG)                  │    │
│  │  • ECDH-derived per-session seed                                │    │
│  │  • Epoch-based profile rotation (100-1000 packets)              │    │
│  │  • Deterministic both ends (same seed = same noise)             │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       │                                                                  │
│       ▼                                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                     SKIN SELECTOR                               │    │
│  │                                                                  │    │
│  │   ┌─────────┐  ┌─────────────┐  ┌───────────┐  ┌───────────┐   │    │
│  │   │  RAW    │  │MIMIC_HTTPS  │  │MIMIC_DNS  │  │MIMIC_VIDEO│   │    │
│  │   │ UDP     │  │WebSocket/TLS│  │DoH Tunnel │  │HLS chunks │   │    │
│  │   └────┬────┘  └──────┬──────┘  └─────┬─────┘  └─────┬─────┘   │    │
│  │        │              │               │              │         │    │
│  │        └──────────────┴───────────────┴──────────────┘         │    │
│  │                         │                                       │    │
│  │                   Auto-selection via probing                    │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│       │                                                                  │
│       ▼                                                                  │
│  NETWORK (ISP/GFW/RKN sees only the skin's traffic pattern)             │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Polymorphic Noise Generator (PNG)

### Design Principles
1. **Per-session uniqueness:** ECDH handshake secret seeds ChaCha20 RNG
2. **Deterministic:** Both peers derive identical noise from shared secret
3. **Epoch rotation:** Profile changes every N packets (prevents long-term analysis)
4. **Distribution matching:** Sample sizes/timing from real-world captures

### Noise Parameters (Per Epoch)
```zig
pub const EpochProfile = struct {
    // Packet size distribution
    size_distribution: enum { Normal, Pareto, Bimodal, LogNormal },
    size_mean: u16,           // e.g., 1440 bytes
    size_stddev: u16,         // e.g., 200 bytes
    
    // Timing distribution
    timing_distribution: enum { Exponential, Gamma, Pareto },
    timing_lambda: f64,       // For exponential: mean inter-packet time
    
    // Dummy packet injection
    dummy_probability: f64,   // 0.0-0.15 (0-15% fake packets)
    dummy_distribution: enum { Uniform, Bursty },
    
    // Epoch boundaries
    epoch_packet_count: u32,  // 100-1000 packets before rotation
};
```

### Seed Derivation
```
Session Secret (ECDH) → HKDF-SHA256 → 256-bit PNG Seed
                                ↓
                    ┌───────────────────────┐
                    │  ChaCha20 RNG State   │
                    └───────────────────────┘
                                ↓
                    ┌───────────────────────┐
                    │  Epoch Profile Chain  │
                    │  (deterministic)      │
                    └───────────────────────┘
```

---

## Transport Skins

### Skin 0: RAW (Unrestricted Networks)
**Use case:** Friendly jurisdictions, LAN, high-performance paths

| Property | Value |
|----------|-------|
| Protocol | UDP direct |
| Port | 7844 (default) |
| Overhead | 0% |
| Latency | Minimal |
| Kenya Viable | ✅ Yes |

**Wire format:**
```
[LWF Frame: 1350 bytes]
```

---

### Skin 1: MIMIC_HTTPS (Standard Censorship Bypass)
**Use case:** GFW, RKN, corporate firewalls (90% coverage)

| Property | Value |
|----------|-------|
| Protocol | WebSocket over TLS 1.3 |
| Port | 443 |
| SNI | Domain fronting capable (ECH preferred) |
| Overhead | ~5% (TLS + WS framing) |
| Latency | +50-100ms |
| Kenya Viable | ✅ Yes |

**TLS Fingerprinting Defense:**
- utls-style parroting (exact Chrome/Firefox JA3 signatures)
- HTTP/2 settings matching browser defaults
- ALPN: `h2, http/1.1`

**Wire format:**
```
TLS 1.3 Record Layer {
    Content Type: Application Data (23)
    TLS Ciphertext: {
        WebSocket Frame {
            FIN: 1
            Opcode: Binary (0x02)
            Masked: 0 (server→client) / 1 (client→server)
            Payload: [PNG Noise] + [LWF Frame]
        }
    }
}
```

**WebSocket Handshake (Cover):**
```
GET /api/v3/stream HTTP/1.1
Host: cdn.cloudflare.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: <base64(random)>
Sec-WebSocket-Version: 13
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)...
```

---

### Skin 2: MIMIC_DNS (Deep Censorship Bypass)
**Use case:** UDP blocked, HTTPS throttled, Iran/Turkmenistan edge cases

| Property | Value |
|----------|-------|
| Protocol | DNS-over-HTTPS (DoH) |
| Endpoint | 1.1.1.1, 8.8.8.8, 9.9.9.9 |
| Overhead | ~300% (Base64url encoding) |
| Latency | +200-500ms |
| Kenya Viable | ⚠️ Marginal (bandwidth-heavy) |

**DNS Tunnel Defenses:**
- **DoH not raw DNS:** Blends with real DoH traffic
- **Query distribution:** Match real DoH query timing (not regular intervals)
- **Label entropy:** Use dictionary words for subdomain labels (not base32)

**Wire format:**
```
POST /dns-query HTTP/2
Host: cloudflare-dns.com
Content-Type: application/dns-message
Accept: application/dns-message

Body: DNS Message {
    Question: <LWF fragment encoded as DNS query name>
    QTYPE: TXT (or HTTPS for larger payloads)
}
```

---

### Skin 3: MIMIC_VIDEO (High-Bandwidth Bypass)
**Use case:** Video-streaming-whitelisted networks, QoS prioritization

| Property | Value |
|----------|-------|
| Protocol | HTTPS with HLS (HTTP Live Streaming) chunk framing |
| Mimics | Netflix, YouTube, Twitch |
| Overhead | ~10% (HLS `.ts` container) |
| Latency | +100-200ms |
| Kenya Viable | ✅ Yes |

**Wire format:**
```
HTTP/2 200 OK
Content-Type: video/mp2t
X-LWF-Sequence: <epoch_packet_num>

Body: [HLS MPEG-TS Container] {
    Adaptation Field: [PNG padding]
    Payload: [LWF Frame]
}
```

---

### Skin 4: STEGO_IMAGE (Nuclear Option)
**Use case:** Total lockdown, emergency fallback only

| Property | Value |
|----------|-------|
| Protocol | HTTPS POST to image hosting (Imgur, etc.) |
| Stego Method | Generative steganography (StyleGAN encoding) |
| Bandwidth | ~1 byte per image (extremely slow) |
| Latency | Seconds to minutes |
| Kenya Viable | ❌ Emergency only |

**Note:** Traditional LSB steganography is broken against ML detection. Use generative encoding only.

---

## Automatic Skin Selection

### Probe Sequence
```zig
pub const SkinProbe = struct {
    /// Attempt skin selection with timeouts
    pub async fn auto_select(relay: RelayEndpoint) !TransportSkin {
        // 1. RAW UDP (fastest, 100ms timeout)
        if (try probe_raw(relay, 100ms)) {
            return .raw;
        }
        
        // 2. HTTPS WebSocket (500ms timeout)
        if (try probe_https(relay, 500ms)) {
            return .mimic_https(relay);
        }
        
        // 3. DNS Tunnel (1s timeout)
        if (try probe_dns(relay, 1s)) {
            return .mimic_dns(relay);
        }
        
        // 4. Nuclear option (no probe, async only)
        return .stego_async(relay);
    }
};
```

### Multi-Path Agility (MPTCP-Style)
```zig
pub const MultiSkinSession = struct {
    primary: TransportSkin,    // 90% bandwidth (HTTPS)
    secondary: TransportSkin,  // 10% bandwidth (DNS keepalive)
    
    /// If primary throttled, signal via secondary
    pub fn adapt_to_throttling(self: *Self) void {
        if (self.primary.detect_throttling()) {
            self.secondary.signal_endpoint_switch();
        }
    }
};
```

---

## Active Probing Defenses

### Honeytrap Responses
When probed without valid session state:
1. **HTTPS Skin:** Respond as legitimate web server (nginx default page)
2. **DNS Skin:** Return NXDOMAIN or valid A record (not relay IP)
3. **Rate limit:** Exponential backoff on failed handshakes

### Reputation Tokens
Prevent rapid relay scanning:
```
Client → Relay: ClientHello + PoW (Argon2, 100ms)
Relay  → Client: ServerHello (only if PoW valid)
```

---

## Implementation Phases

### Phase 1: Foundation (Sprint 5)
- [ ] PNG core (ChaCha20 RNG, epoch rotation)
- [ ] RAW skin (baseline)
- [ ] MIMIC_HTTPS skin (WebSocket + TLS)
- [ ] utls fingerprint parroting
- [ ] Automatic probe selection
- [ ] Noise Protocol Framework (X25519, ChaCha20-Poly1305)
- [ ] Noise_XX handshake implementation

### Phase 2: Deep Bypass (Sprint 6)
- [ ] MIMIC_DNS skin (DoH tunnel)
- [ ] ECH support (Encrypted Client Hello)
- [ ] Active probing defenses
- [ ] Multi-path agility

### Phase 3: Advanced (Sprint 7)
- [ ] MIMIC_VIDEO skin (HLS framing)
- [ ] Distribution matching from real captures
- [ ] Steganography (generative only)
- [ ] Formal security audit

---

## Noise Protocol Framework Integration

### Overview
Transport Skins provide **camouflage** — they make traffic look like benign protocols. But camouflage without encryption is just obfuscation. We integrate the **Noise Protocol Framework** (noiseprotocol.org) to provide modern, lightweight cryptographic security.

**Why Noise?**
- Used by Signal, WireGuard, and other production systems
- Simple, auditable state machine
- No cipher agility attacks (one cipher suite per pattern)
- Forward secrecy + identity hiding built-in

### Architecture: Noise + MIMIC

```
┌─────────────────────────────────────────────────────────────┐
│              NOISE + MIMIC INTEGRATION                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Application Layer                                           │
│       │                                                      │
│       ▼                                                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  NOISE PROTOCOL (cryptographic security)              │  │
│  │  • X25519 key exchange                                │  │
│  │  • ChaCha20-Poly1305 AEAD                             │  │
│  │  • XX, IK, NN patterns                                │  │
│  └───────────────────────────────────────────────────────┘  │
│       │                                                      │
│       ▼                                                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  POLYMORPHIC NOISE GENERATOR (traffic shaping)        │  │
│  │  • Packet size padding                                │  │
│  │  • Timing jitter                                      │  │
│  │  • Dummy injection                                    │  │
│  └───────────────────────────────────────────────────────┘  │
│       │                                                      │
│       ▼                                                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  TRANSPORT SKIN (protocol camouflage)                 │  │
│  │  • MIMIC_HTTPS (WebSocket/TLS)                        │  │
│  │  • MIMIC_DNS (DoH tunnel)                             │  │
│  │  • MIMIC_QUIC (HTTP/3)                                │  │
│  └───────────────────────────────────────────────────────┘  │
│       │                                                      │
│       ▼                                                      │
│  NETWORK (DPI sees only the skin's traffic pattern)         │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Supported Patterns

| Pattern | Use Case | Properties |
|---------|----------|------------|
| **Noise_XX** | General purpose | Mutual authentication, identity hiding |
| **Noise_IK** | Client-to-server (known key) | 0-RTT, initiator authentication deferred |
| **Noise_NN** | Ephemeral-only | No authentication, encryption only |

### Handshake Example: Noise_XX

```
Initiator                          Responder
─────────────────────────────────────────────────
Generate e

   ───── e ─────────────────────>

                                  Receive e
                                  Generate e
                                  DH(e, re)

   <──── e, ee, s, es ──────────

Receive e
DH(e, re)
Decrypt s
DH(s, re)

   ───── s, se ────────────────>

                                  Receive s
                                  DH(e, rs)
                                  DH(s, rs)
                                  Split()

Split()  ───────────────────────  Transport Ready
```

### Security Properties

| Property | Noise_XX | Noise_IK | Provided By |
|----------|----------|----------|-------------|
| **Forward Secrecy** | ✅ | ⚠️ (deferred) | Ephemeral DH |
| **Identity Hiding** | ✅ Initiator | ❌ | XX pattern order |
| **Mutual Auth** | ✅ | ✅ | Static key exchange |
| **0-RTT Encryption** | ❌ | ✅ | Pre-shared responder key |
| **KCI Resistance** | ✅ | ⚠️ | Key compromise impersonation |

### Integration Benefits

1. **Camouflage + Security:** MIMIC skins fool DPI; Noise encryption ensures confidentiality
2. **Forward Secrecy:** Even if static keys are compromised, past sessions remain secure
3. **Identity Hiding:** Static public keys are encrypted during handshake
4. **Lightweight:** ~2KB RAM per session; suitable for Kenya-class devices

---

## Kenya Compliance Check

| Skin | RAM | Binary Size | Cloud Calls | Viable? |
|------|-----|-------------|-------------|---------|
| RAW | <1MB | +0KB | None | ✅ |
| MIMIC_HTTPS | <2MB | +50KB (TLS) | None (embedded TLS) | ✅ |
| MIMIC_DNS | <1MB | +10KB | DoH to public resolver | ✅ |
| MIMIC_VIDEO | <2MB | +20KB (HLS) | None | ✅ |
| STEGO | >100MB | +500MB (ML models) | Image host upload | ❌ |

---

## Security Considerations

### TLS Fingerprinting (Critical)
**Risk:** Rustls default JA3 signature is trivially blockable.  
**Mitigation:** Mandatory utls parroting; exact Chrome/Firefox match.

### DNS Tunnel Detectability (High)
**Risk:** Base32 subdomains have high entropy (4.8 vs 2.5 bits/char).  
**Mitigation:** Use DoH to major providers; dictionary-word labels.

### Flow Correlation (Medium)
**Risk:** Long-term traffic statistics identify protocol.  
**Mitigation:** PNG epoch rotation; per-session uniqueness.

---

## References

1. **utls:** [github.com/refraction-networking/utls](https://github.com/refraction-networking/utls) — TLS fingerprint parroting
2. **Snowflake:** [Tor Project](https://snowflake.torproject.org/) — WebRTC pluggable transport
3. **Conjure:** [refraction.network](https://refraction.network/) — Refraction networking
4. **ECH:** RFC 9446 — Encrypted Client Hello
5. **DoH:** RFC 8484 — DNS over HTTPS
6. **Noise Protocol:** [noiseprotocol.org](https://noiseprotocol.org/) — Modern crypto framework
7. **WireGuard:** [wireguard.com](https://www.wireguard.com/) — Noise_IK in production

---

*"The submarine wears chameleon skin. The hull remains the same."*  
⚡️
