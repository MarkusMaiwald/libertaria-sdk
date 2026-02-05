# DIGEST.md — Libertaria for Humans

*The 5-minute briefing for builders, thinkers, and exit strategists*

---

## What Is This?

Libertaria is **sovereign infrastructure** — tools for humans and AI agents to communicate, identify, and coordinate without platform control.

Think of it as: **Signal's privacy + Bitcoin's sovereignty + Tor's censorship resistance**, rebuilt from first principles in Zig.

---

## The Stack (Top to Bottom)

```
L4+  Applications    →  Your apps inherit sovereignty by default
L3   Governance      →  Chapters, federation, betrayal economics
L2   Session         →  Resilient connections, offline-first
L1   Identity        →  Self-sovereign keys, trust graphs
L0   Transport       →  Censorship-resistant, traffic camouflage
```

---

## Key Innovations

### 🔒 MIMIC Skins (L0)
Your traffic looks like HTTPS, DNS, or QUIC. Firewalls see Netflix; you get Signal-grade encryption.

### 🔑 SoulKey (L1)
One seed → infinite identities. Deterministic derivation means portable, revocable, recoverable keys.

### 🕸️ QVL — Quasar Vector Lattice (L1)
A trust graph that detects betrayal before it happens. Mathematical reputation, not social media points.

### 🚪 Exit-First Design (L3)
Every conversation, every community, every protocol can be forked without losing history. Loyalty is earned, not enforced.

---

## Quick Start

```bash
# Clone
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack

# Build
zig build

# Test (166 passing)
zig build test

# Run Capsule node
zig build run
```

---

## Why Not [Alternative]?

| Alternative | Why Not |
|:------------|:--------|
| **Signal** | Centralized. Can be blocked. Phone number required. |
| **Matrix** | Complexity explosion. Federation doesn't solve capture. |
| **Nostr** | No encryption. Spam paradise. Relay capture. |
| **Ethereum** | 15 TPS. $50 fees. Smart contracts are slow databases. |
| **Web5/TBD** | Corporate solution, not sovereign infrastructure. |

---

## Where to Start Reading

**5 minutes:** This file (you're done!)

**30 minutes:** 
- `README.md` — Full architecture
- `docs/rfcs/RFC-0015_Transport_Skins.md` — Why we evade rather than encrypt

**2 hours:**
- `core/l0-transport/noise.zig` — See the crypto
- `core/l1-identity/qvl/` — Trust graph implementation
- `ONBOARDING.md` — How to contribute

**Deep dive:**
- `docs/rfcs/` — All specifications
- `DECISIONS.md` — Why we built it this way
- `blog/libertaria.app` — Philosophy and context

---

## The Licenses (Why This Matters)

- **Core (L0-L3):** LCL-1.0 — The tribe owns the code. Can't be captured.
- **SDK (L4+):** LSL-1.0 — Build proprietary apps on top. Your code stays yours.
- **Docs:** LUL-1.0 — Ideas spread freely.

**No CLA.** You keep your copyright. We keep our reciprocity.

---

## Get Involved

**Code:** `zig build test` → find failing test → fix → PR

**Ideas:** Open an issue. Challenge our assumptions. "Red team" our design.

**Spread:** Write about sovereignty. Point people here. Exit is contagious.

---

## The One-Sentence Pitch

> Libertaria is infrastructure for a world where you can leave any platform without losing your identity, your relationships, or your history.

---

*Questions? Read `AGENT.md` if you're an AI, or open an issue if you're human.*

⚡️
