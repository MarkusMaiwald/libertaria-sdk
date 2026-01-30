# Libertaria SDK

**The Core Protocol Stack for Libertaria Applications**

**Version:** 0.1.0-alpha
**License:** TBD
**Language:** Zig 0.15.x
**Status:** Alpha (L0+L1 Foundation)

---

## What is Libertaria SDK?

The Libertaria SDK provides the foundational L0 (Transport) and L1 (Identity/Crypto) layers for building Libertaria-compatible applications.

**It implements:**
- **RFC-0000:** Libertaria Wire Frame Protocol (LWF)
- **RFC-0100:** Entropy Stamps (anti-spam PoW)
- **RFC-0110:** Membrane Agent primitives
- **RFC-0250:** Larval Identity Protocol (SoulKey)

**Design Goals:**
- ✅ **Kenya-compliant:** <200 KB binary size
- ✅ **Static linking:** No runtime dependencies
- ✅ **Cross-platform:** ARM, MIPS, RISC-V, x86, WebAssembly
- ✅ **Zero-copy:** Efficient packet processing
- ✅ **Auditable:** Clear, explicit code

---

## Layers

### L0: Transport Layer
**Module:** `l0-transport/`

Implements the core wire protocol:
- **LWF Frame Codec** - Encode/decode wire frames
- **UTCP** - Reliable transport over UDP (future)
- **Frame Validation** - Checksum, signature verification
- **Priority Queues** - Traffic shaping

**Key Files:**
- `lwf.zig` - LWF frame structure and codec
- `utcp.zig` - UTCP transport (future)
- `validation.zig` - Frame validation logic

---

### L1: Identity & Cryptography Layer
**Module:** `l1-identity/`

Implements identity and cryptographic primitives:
- **SoulKey** - Ed25519 signing, X25519 key agreement
- **Entropy Stamps** - Proof-of-work anti-spam
- **AEAD Encryption** - XChaCha20-Poly1305
- **Post-Quantum** - Kyber-768 KEM (future)

**Key Files:**
- `soulkey.zig` - Identity keypair management
- `entropy.zig` - Entropy Stamp creation/verification
- `crypto.zig` - Encryption primitives

---

## Installation

### Option 1: Git Submodule (Recommended)

```bash
# Add SDK to your Libertaria app
cd your-libertaria-app
git submodule add https://git.maiwald.work/Libertaria/libertaria-sdk libs/libertaria-sdk
git submodule update --init
```

### Option 2: Manual Clone

```bash
# Clone SDK
git clone https://git.maiwald.work/Libertaria/libertaria-sdk
cd libertaria-sdk
zig build test  # Verify it works
```

### Option 3: Zig Package Manager (Future)

```zig
// build.zig.zon
.{
    .name = "my-app",
    .version = "0.1.0",
    .dependencies = .{
        .libertaria_sdk = .{
            .url = "https://git.maiwald.work/Libertaria/libertaria-sdk/archive/v0.1.0.tar.gz",
            .hash = "1220...",
        },
    },
}
```

---

## Usage

### Basic Integration

```zig
// your-app/build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Link Libertaria SDK (static)
    const sdk_l0 = b.addStaticLibrary(.{
        .name = "libertaria_l0",
        .root_source_file = b.path("libs/libertaria-sdk/l0-transport/lwf.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdk_l1 = b.addStaticLibrary(.{
        .name = "libertaria_l1",
        .root_source_file = b.path("libs/libertaria-sdk/l1-identity/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Your app
    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibrary(sdk_l0);
    exe.linkLibrary(sdk_l1);

    b.installArtifact(exe);
}
```

### Example: Send LWF Frame

```zig
const std = @import("std");
const lwf = @import("libs/libertaria-sdk/l0-transport/lwf.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create LWF frame
    var frame = try lwf.LWFFrame.init(allocator, 100);
    defer frame.deinit(allocator);

    frame.header.service_type = std.mem.nativeToBig(u16, 0x0A00); // FEED_WORLD_POST
    frame.header.flags = 0x01; // ENCRYPTED

    // Encode to bytes
    const encoded = try frame.encode(allocator);
    defer allocator.free(encoded);

    std.debug.print("Encoded frame: {} bytes\n", .{encoded.len});
}
```

---

## Building the SDK

### Build Static Libraries

```bash
cd libertaria-sdk
zig build

# Output:
# zig-out/lib/liblibertaria_l0.a
# zig-out/lib/liblibertaria_l1.a
```

### Run Tests

```bash
zig build test

# Should output:
# All tests passed.
```

### Build Examples

```bash
zig build examples
./zig-out/bin/lwf_example
```

---

## SDK Structure

```
libertaria-sdk/
├── README.md                   # This file
├── LICENSE                     # TBD
├── build.zig                   # SDK build system
├── l0-transport/               # L0: Transport layer
│   ├── lwf.zig                 # LWF frame codec
│   ├── utcp.zig                # UTCP transport (future)
│   ├── validation.zig          # Frame validation
│   └── test_lwf.zig            # L0 tests
├── l1-identity/                # L1: Identity & crypto
│   ├── soulkey.zig             # SoulKey (Ed25519/X25519)
│   ├── entropy.zig             # Entropy Stamps
│   ├── crypto.zig              # XChaCha20-Poly1305
│   └── test_crypto.zig         # L1 tests
├── tests/                      # Integration tests
│   ├── integration_test.zig
│   └── fixtures/
├── docs/                       # Documentation
│   ├── API.md                  # API reference
│   ├── INTEGRATION.md          # Integration guide
│   └── ARCHITECTURE.md         # Architecture overview
└── examples/                   # Example code
    ├── lwf_example.zig
    ├── encryption_example.zig
    └── entropy_example.zig
```

---

## Performance

### Binary Size

```
Static library sizes (ReleaseSafe):
  liblibertaria_l0.a: ~80 KB
  liblibertaria_l1.a: ~120 KB
  Total SDK:          ~200 KB

App with SDK linked:  ~500 KB (Feed client)
```

### Benchmarks (Raspberry Pi 4)

```
LWF Frame Encode:     ~5 µs
LWF Frame Decode:     ~6 µs
XChaCha20 Encrypt:    ~12 µs (1 KB payload)
Ed25519 Sign:         ~45 µs
Ed25519 Verify:       ~120 µs
Entropy Stamp (d=20): ~1.2 seconds
```

---

## Versioning

The SDK follows semantic versioning:

- **0.1.x** - Alpha (L0+L1 foundation)
- **0.2.x** - Beta (UTCP, OPQ)
- **0.3.x** - RC (Post-quantum)
- **1.0.0** - Stable

**Breaking changes:** Major version bump (1.x → 2.x)
**New features:** Minor version bump (1.1 → 1.2)
**Bug fixes:** Patch version bump (1.1.1 → 1.1.2)

---

## Dependencies

**Zero runtime dependencies!**

**Build dependencies:**
- Zig 0.15.x or later
- Git (for submodules)

**The SDK uses only Zig's stdlib:**
- `std.crypto` - Cryptographic primitives
- `std.mem` - Memory utilities
- `std.net` - Network types (future)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (TODO)

**Code Style:**
- Follow Zig conventions
- Run `zig fmt` before committing
- Add tests for new features
- Keep functions < 50 lines
- Document public APIs

---

## Applications Using This SDK

- **[Feed](https://git.maiwald.work/Libertaria/Feed)** - Decentralized social protocol
- **[LatticePost](https://git.maiwald.work/Libertaria/LatticePost)** - E2EE messaging (future)
- **[Archive Node](https://git.maiwald.work/Libertaria/ArchiveNode)** - Content archival (future)

---

## Related Documents

- **[RFC-0000](../libertaria/03-TECHNICAL/L0-TRANSPORT/RFC-0000_LIBERTARIA_WIRE_FRAME_v0_3_0.md)** - Wire Frame Protocol
- **[RFC-0100](../libertaria/03-TECHNICAL/L1-IDENTITY/RFC-0100_ENTROPY_STAMP_SCHEMA_v0_2_0.md)** - Entropy Stamps
- **[ADR-003](../libertaria/03-TECHNICAL/ADR-003_SPLIT_STACK_ZIG_RUST.md)** - Split-stack architecture

---

## License

TBD (awaiting decision)

---

## Contact

**Repository:** https://git.maiwald.work/Libertaria/libertaria-sdk
**Issues:** https://git.maiwald.work/Libertaria/libertaria-sdk/issues
**Author:** Markus Maiwald

---

**Status:** Alpha - L0+L1 foundation complete
**Next:** UTCP transport, OPQ, post-quantum crypto

---

*"The hull is forged in Zig. The protocol is sovereign. The submarine descends."*
