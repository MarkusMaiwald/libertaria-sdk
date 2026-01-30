# Libertaria SDK Integration Guide

**For:** Application developers building on Libertaria
**Version:** 0.1.0-alpha

---

## Quick Start (5 Minutes)

### 1. Add SDK to Your Project

```bash
cd your-libertaria-app
git submodule add https://git.maiwald.work/Libertaria/libertaria-sdk libs/libertaria-sdk
git submodule update --init
```

### 2. Update build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Link Libertaria SDK
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

### 3. Use SDK in Your Code

```zig
const std = @import("std");
const lwf = @import("libs/libertaria-sdk/l0-transport/lwf.zig");
const crypto = @import("libs/libertaria-sdk/l1-identity/crypto.zig");

pub fn main() !void {
    // Your code here
}
```

### 4. Build

```bash
zig build
./zig-out/bin/my-app
```

---

## Common Use Cases

### Creating LWF Frames

```zig
const lwf = @import("libs/libertaria-sdk/l0-transport/lwf.zig");

pub fn createWorldPost(allocator: std.mem.Allocator, content: []const u8) !lwf.LWFFrame {
    // Create frame
    var frame = try lwf.LWFFrame.init(allocator, content.len);

    // Set headers
    frame.header.service_type = std.mem.nativeToBig(u16, 0x0A00); // FEED_WORLD_POST
    frame.header.flags = lwf.LWFFlags.ENCRYPTED | lwf.LWFFlags.SIGNED;
    frame.header.timestamp = std.mem.nativeToBig(u64, @as(u64, @intCast(std.time.timestamp())));
    frame.header.payload_len = std.mem.nativeToBig(u16, @as(u16, @intCast(content.len)));

    // Copy content
    @memcpy(frame.payload, content);

    // Update checksum
    frame.updateChecksum();

    return frame;
}
```

### Encrypting Payloads

```zig
const crypto = @import("libs/libertaria-sdk/l1-identity/crypto.zig");

pub fn encryptMessage(
    allocator: std.mem.Allocator,
    plaintext: []const u8,
    recipient_pubkey: [32]u8,
    sender_private: [32]u8,
) !crypto.EncryptedPayload {
    return crypto.encryptPayload(plaintext, recipient_pubkey, sender_private, allocator);
}
```

### Validating Frames

```zig
pub fn validateFrame(frame: *const lwf.LWFFrame) !void {
    // Check magic
    if (!frame.header.isValid()) {
        return error.InvalidMagic;
    }

    // Verify checksum
    if (!frame.verifyChecksum()) {
        return error.ChecksumMismatch;
    }

    // Check timestamp freshness (5 minute window)
    const now = @as(u64, @intCast(std.time.timestamp()));
    const frame_time = std.mem.bigToNative(u64, frame.header.timestamp);
    if (now - frame_time > 300) {
        return error.StaleFrame;
    }
}
```

---

## SDK Modules

### L0: Transport (`l0-transport/`)

**lwf.zig** - LWF frame codec

```zig
// Import
const lwf = @import("libs/libertaria-sdk/l0-transport/lwf.zig");

// Types
lwf.LWFFrame
lwf.LWFHeader
lwf.LWFTrailer
lwf.FrameClass
lwf.LWFFlags

// Functions
frame.init(allocator, payload_size)
frame.deinit(allocator)
frame.encode(allocator)
lwf.LWFFrame.decode(allocator, data)
frame.calculateChecksum()
frame.verifyChecksum()
frame.updateChecksum()
```

---

### L1: Identity & Crypto (`l1-identity/`)

**crypto.zig** - Encryption primitives

```zig
// Import
const crypto = @import("libs/libertaria-sdk/l1-identity/crypto.zig");

// Constants
crypto.WORLD_PUBLIC_KEY

// Types
crypto.EncryptedPayload

// Functions
crypto.encryptPayload(plaintext, recipient_pubkey, sender_private, allocator)
crypto.decryptPayload(encrypted, recipient_private, allocator)
crypto.encryptWorld(plaintext, sender_private, allocator)
crypto.decryptWorld(encrypted, recipient_private, allocator)
crypto.generateNonce()
```

---

## Version Pinning

### Pin to Specific Commit

```bash
cd libs/libertaria-sdk
git checkout abc123  # Specific commit
cd ../..
git add libs/libertaria-sdk
git commit -m "Pin SDK to commit abc123"
```

### Pin to Tagged Version

```bash
cd libs/libertaria-sdk
git checkout v0.1.0  # Tagged release
cd ../..
git add libs/libertaria-sdk
git commit -m "Pin SDK to v0.1.0"
```

### Update SDK

```bash
cd libs/libertaria-sdk
git pull origin main
cd ../..
git add libs/libertaria-sdk
git commit -m "Update SDK to latest"

# Rebuild
zig build
```

---

## Binary Size Optimization

### Use ReleaseSafe

```bash
zig build -Doptimize=ReleaseSafe
```

**Typical sizes:**
- L0 library: ~80 KB
- L1 library: ~120 KB
- App with SDK: ~500 KB

### Use ReleaseSmall (Kenya Compliance)

```bash
zig build -Doptimize=ReleaseSmall
```

**Optimized sizes:**
- L0 library: ~60 KB
- L1 library: ~90 KB
- App with SDK: ~350 KB

---

## Testing

### Run SDK Tests

```bash
cd libs/libertaria-sdk
zig build test
```

### Run SDK Examples

```bash
cd libs/libertaria-sdk
zig build examples
./zig-out/bin/lwf_example
./zig-out/bin/crypto_example
```

### Test Your Integration

```zig
// your-app/tests/sdk_test.zig
const std = @import("std");
const lwf = @import("../libs/libertaria-sdk/l0-transport/lwf.zig");

test "SDK integration works" {
    const allocator = std.testing.allocator;

    var frame = try lwf.LWFFrame.init(allocator, 100);
    defer frame.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 64 + 100 + 36), frame.size());
}
```

---

## Cross-Compilation

### ARM (Raspberry Pi)

```bash
zig build -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseSmall
```

### MIPS (Router)

```bash
zig build -Dtarget=mips-linux-musl -Doptimize=ReleaseSmall
```

### RISC-V

```bash
zig build -Dtarget=riscv64-linux-musl -Doptimize=ReleaseSmall
```

### WebAssembly

```bash
zig build -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall
```

---

## Troubleshooting

### SDK Not Found

```
error: file not found: libs/libertaria-sdk/l0-transport/lwf.zig
```

**Solution:**
```bash
git submodule update --init
```

### Link Errors

```
error: undefined reference to `crypto_sign`
```

**Solution:** Ensure both L0 and L1 libraries are linked:
```zig
exe.linkLibrary(sdk_l0);
exe.linkLibrary(sdk_l1);
```

### Version Mismatch

```
error: incompatible ABI version
```

**Solution:** Update SDK to compatible version or rebuild app:
```bash
cd libs/libertaria-sdk
git checkout v0.1.0  # Match your SDK version
cd ../..
zig build clean
zig build
```

---

## Performance Tips

### 1. Pre-Allocate Frames

```zig
// Bad: Allocate every time
for (messages) |msg| {
    var frame = try lwf.LWFFrame.init(allocator, msg.len);
    defer frame.deinit(allocator);
    // ...
}

// Good: Reuse buffer
var buffer = try allocator.alloc(u8, max_payload_size);
defer allocator.free(buffer);

for (messages) |msg| {
    var frame = lwf.LWFFrame{
        .header = lwf.LWFHeader.init(),
        .payload = buffer[0..msg.len],
        .trailer = lwf.LWFTrailer.init(),
    };
    // ...
}
```

### 2. Batch Encryption

```zig
// Encrypt multiple messages with same shared secret
const shared_secret = try std.crypto.dh.X25519.scalarmult(sender_private, recipient_public);

for (messages) |msg| {
    // Reuse shared_secret instead of re-computing
}
```

### 3. Use ArenaAllocator for Short-Lived Data

```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
const allocator = arena.allocator();

// All allocations freed together
```

---

## Next Steps

1. **Read SDK examples:** `libs/libertaria-sdk/examples/`
2. **Check API docs:** `libs/libertaria-sdk/docs/API.md` (TODO)
3. **Join development:** https://git.maiwald.work/Libertaria/libertaria-sdk

---

**Need help?** Open an issue: https://git.maiwald.work/Libertaria/libertaria-sdk/issues
