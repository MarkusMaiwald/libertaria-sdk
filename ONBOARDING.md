# ONBOARDING.md — Contributing to Libertaria

*From first commit to core contributor*

---

## Welcome

You're here because you believe digital sovereignty should be the default, not a privilege. This guide gets you productive in 30 minutes.

---

## Prerequisites

- **Zig 0.15.2+** — [ziglang.org/download](https://ziglang.org/download/)
- **Git** — For version control
- **2+ hours** — To read, build, and understand

Optional but helpful:
- **liboqs** — For post-quantum crypto (see `vendor/liboqs/`)
- **argon2** — For key derivation (bundled in `vendor/argon2/`)

---

## 5-Minute Setup

```bash
# 1. Clone
git clone https://github.com/libertaria-project/libertaria-stack.git
cd libertaria-stack

# 2. Build
zig build

# 3. Test
zig build test

# 4. Run example
zig build examples
./zig-out/bin/lwf_example
```

**Expected:** All tests pass, examples run without errors.

---

## Repository Structure

```
libertaria-stack/
├── core/                    # LCL-1.0 licensed (viral)
│   ├── l0-transport/        # Transport layer
│   ├── l1-identity/         # Identity, crypto, QVL
│   ├── l2_session/          # Session management
│   ├── l2-federation/       # Cross-chain bridging
│   └── l2-membrane/         # Policy enforcement
├── sdk/                     # LSL-1.0 licensed (business-friendly)
│   ├── l4-feed/             # Temporal event store
│   └── janus-sdk/           # Language bindings
├── apps/                    # LUL-1.0 licensed (unbound)
│   └── examples/            # Example applications
├── docs/                    # Specifications and RFCs
│   └── rfcs/                # Request for Comments
└── capsule-core/            # Reference node implementation
```

---

## Finding Your First Contribution

### Good First Issues

Look for issues labeled:
- `good-first-issue` — Self-contained, well-defined
- `documentation` — Typos, clarifications, examples
- `test-coverage` — Add tests for existing code

### Areas Needing Help

| Area | Skills Needed | Impact |
|:-----|:--------------|:-------|
| **Test Coverage** | Zig | High — increase reliability |
| **Documentation** | Writing | High — lower barrier to entry |
| **Porting** | Rust/Go/TS | Medium — expand ecosystem |
| **Benchmarks** | Zig + analysis | Medium — prove performance |
| **Security Review** | Crypto expertise | Critical — find vulnerabilities |

---

## Development Workflow

### 1. Fork and Branch

```bash
# Fork on GitHub, then:
git clone https://github.com/YOUR_USERNAME/libertaria-stack.git
cd libertaria-stack
git checkout -b feature/your-feature-name
```

### 2. Make Changes

```bash
# Edit code
vim core/l0-transport/noise.zig

# Test your changes
zig test core/l0-transport/noise.zig

# Run full test suite
zig build test
```

### 3. Commit

We use [Conventional Commits](https://www.conventionalcommits.org/):

```bash
# Format: type(scope): description

git commit -m "feat(l0): add QUIC transport skin"
git commit -m "fix(l1): correct QVL path calculation"
git commit -m "docs: clarify SoulKey derivation"
git commit -m "test(l2): add session rotation tests"
```

Types:
- `feat` — New feature
- `fix` — Bug fix
- `docs` — Documentation only
- `test` — Tests only
- `refactor` — Code change, no behavior change
- `perf` — Performance improvement
- `chore` — Build, tooling, etc.

### 4. Push and PR

```bash
git push origin feature/your-feature-name
```

Open a PR on GitHub with:
- Clear description of what and why
- Reference to any related issues
- Test results (`zig build test` output)

---

## Code Standards

### Zig Style

```zig
// Use explicit types
const count: u32 = 42;

// Error unions, not exceptions
fn mayFail() !Result { ... }

// Defer cleanup
defer allocator.free(buffer);

// Comptime when possible
fn max(comptime T: type, a: T, b: T) T { ... }
```

### Documentation

Every public function needs a doc comment:

```zig
/// Derives a deterministic DID from the SoulKey.
/// Context string provides domain separation.
/// Returns error.InvalidContext if context exceeds 64 bytes.
pub fn deriveDid(self: *SoulKey, context: []const u8) !Did { ... }
```

### Testing

```zig
test "SoulKey derivation is deterministic" {
    const seed = [_]u8{0x01} ** 32;
    var sk1 = try SoulKey.init(testing.allocator, seed);
    var sk2 = try SoulKey.init(testing.allocator, seed);
    
    const did1 = try sk1.deriveDid("test");
    const did2 = try sk2.deriveDid("test");
    
    try testing.expectEqualStrings(did1, did2);
}
```

---

## Architecture Decision Records (ADRs)

Major decisions are documented in `DECISIONS.md`. Before proposing changes that affect:
- Protocol design
- Cryptographic primitives
- API compatibility
- Licensing implications

...read existing ADRs and consider writing a new one.

---

## Communication

### Where to Ask

- **GitHub Issues** — Bug reports, feature requests
- **GitHub Discussions** — Questions, ideas, RFCs
- **Moltbook: m/Libertaria** — Real-time chat

### Code of Conduct

1. **Be direct** — German-style honesty over corporate smoothness
2. **Challenge ideas** — Not people
3. **Ship beats perfect** — Working code > perfect plans
4. **Document everything** — Future you will thank present you

---

## Learning Path

### Week 1: Understand
- Read `DIGEST.md` (5 min)
- Read `README.md` (30 min)
- Build and run tests
- Read one RFC (`RFC-0015_Transport_Skins.md`)

### Week 2: Contribute
- Fix a typo in documentation
- Add a test for existing code
- Review a PR

### Week 3: Build
- Implement a small feature
- Write an ADR for a design decision
- Help onboard another contributor

### Month 2: Lead
- Own a component
- Mentor new contributors
- Propose architectural changes

---

## Recognition

Contributors are recognized in:
- `CONTRIBUTORS.md` (all contributors)
- Release notes (significant contributions)
- Commit history (permanent)

**No CLA required.** You keep your copyright.

---

## Questions?

- **Quick:** Check `AGENT.md` (AI-oriented) or `DIGEST.md` (human-oriented)
- **Deep:** Read `docs/rfcs/`
- **Urgent:** Open a GitHub issue
- **Philosophical:** Read `blog/libertaria.app`

---

## The Bottom Line

We move fast, build correctly, and ship working code. If you're here, you already understand why this matters. Let's build exit infrastructure together.

⚡️
