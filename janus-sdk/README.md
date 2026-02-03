# Libertaria SDK for Janus

> Sovereign; Kinetic; Anti-Fragile.

The Libertaria SDK provides primitives for building sovereign agent networks on top of Janus.

**Status:** v0.1.0-alpha (2026-02-03)

## Core Modules

| Module | File | Status | Purpose |
|--------|------|--------|---------|
| `identity` | `identity.jan` | ✅ Draft | Cryptographic agent identity with rotation/burn |
| `message` | `message.jan` | ✅ Draft | Signed, content-addressed messages |
| `context` | `context.jan` | ✅ Draft | NCP (Nexus Context Protocol) implementation |
| `memory` | `memory.jan` | ✅ Draft | Vector-backed semantic memory (LanceDB) |
| `lib` | `lib.jan` | ✅ Draft | Unified API export |

## Quick Start

```janus
import libertaria

-- Create sovereign agent
let agent = libertaria.create_sovereign_agent()

-- Create identity with rotation capability
let (new_id, old_id) = identity.rotate(agent.identity)

-- Send signed message
let msg = message.create(
  from = agent.identity,
  content_type = Text,
  content = bytes.from_string("Hello Sovereigns!")
)

-- Create hierarchical context
let ctx = context.create({})
let sub_ctx = context.fork(ctx, reason = "Sub-conversation")?

-- Store in semantic memory
let emb = memory.embed(message.content(msg))
let vs = memory.store(agent.memory, message.id(msg), emb, "...")
```

## Design Principles

1. **Exit is Voice** — Agents can leave, taking their data cryptographically (`identity.burn`)
2. **Profit = Honesty** — Economic stakes align incentives (staking module planned)
3. **Code is Law** — No central moderation, only protocol rules
4. **Binary APIs** — gRPC/MsgPack/QUIC over REST

## Architecture

```
┌─────────────────────────────────────────────┐
│           Libertaria SDK                     │
├──────────┬──────────┬──────────┬────────────┤
│ Identity │ Message  │ Context  │ Memory     │
│          │          │ (NCP)    │ (LanceDB)  │
├──────────┴──────────┴──────────┴────────────┤
│              Janus Standard Library          │
├─────────────────────────────────────────────┤
│           Janus Compiler (:service)          │
└─────────────────────────────────────────────┘
```

## Next Steps

- [ ] Staking/Economics module (spam prevention)
- [ ] Channel module (QUIC transport)
- [ ] Discovery module (DHT-based agent lookup)
- [ ] Governance module (voting, proposals)
- [ ] Test suite
- [ ] Integration with Janus compiler

## License

MIT + Libertaria Commons Clause

*Forge burns bright. The Exit is being built.*

⚡️
