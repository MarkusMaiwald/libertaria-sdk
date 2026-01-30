const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ========================================================================
    // L0: Transport Layer
    // ========================================================================
    const l0_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/lwf.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // Crypto: SHA3/SHAKE & FIPS 202
    // ========================================================================
    const crypto_shake_mod = b.createModule(.{
        .root_source_file = b.path("src/crypto/shake.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crypto_fips202_mod = b.createModule(.{
        .root_source_file = b.path("src/crypto/fips202_bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    const crypto_exports_mod = b.createModule(.{
        .root_source_file = b.path("src/crypto/exports.zig"),
        .target = target,
        .optimize = optimize,
    });
    crypto_exports_mod.addImport("fips202_bridge", crypto_fips202_mod);

    // ========================================================================
    // L1: Identity & Crypto Layer
    // ========================================================================
    const l1_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add crypto modules as imports to L1
    l1_mod.addImport("shake", crypto_shake_mod);
    l1_mod.addImport("fips202_bridge", crypto_fips202_mod);

    // ========================================================================
    // L1 Modules: SoulKey, Entropy, Prekey (Phase 2B + 2C)
    // ========================================================================
    const l1_soulkey_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/soulkey.zig"),
        .target = target,
        .optimize = optimize,
    });

    const l1_entropy_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/entropy.zig"),
        .target = target,
        .optimize = optimize,
    });

    const l1_prekey_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/prekey.zig"),
        .target = target,
        .optimize = optimize,
    });

    const l1_did_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/did.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // Tests (with C FFI support for Argon2 + liboqs)
    // ========================================================================

    // Crypto tests (SHA3/SHAKE)
    const crypto_tests = b.addTest(.{
        .root_module = crypto_shake_mod,
    });
    const run_crypto_tests = b.addRunArtifact(crypto_tests);

    // Crypto FFI bridge tests
    const crypto_ffi_tests = b.addTest(.{
        .root_module = crypto_fips202_mod,
    });
    const run_crypto_ffi_tests = b.addRunArtifact(crypto_ffi_tests);

    // L0 tests
    const l0_tests = b.addTest(.{
        .root_module = l0_mod,
    });
    const run_l0_tests = b.addRunArtifact(l0_tests);

    // L1 SoulKey tests (Phase 2B)
    const l1_soulkey_tests = b.addTest(.{
        .root_module = l1_soulkey_mod,
    });
    const run_l1_soulkey_tests = b.addRunArtifact(l1_soulkey_tests);

    // L1 Entropy tests (Phase 2B)
    const l1_entropy_tests = b.addTest(.{
        .root_module = l1_entropy_mod,
    });
    l1_entropy_tests.addCSourceFiles(.{
        .files = &.{
            "vendor/argon2/src/argon2.c",
            "vendor/argon2/src/core.c",
            "vendor/argon2/src/blake2/blake2b.c",
            "vendor/argon2/src/thread.c",
            "vendor/argon2/src/encoding.c",
            "vendor/argon2/src/opt.c",
        },
        .flags = &.{
            "-std=c99",
            "-O3",
            "-fPIC",
            "-DHAVE_PTHREAD",
        },
    });
    l1_entropy_tests.addIncludePath(b.path("vendor/argon2/include"));
    l1_entropy_tests.linkLibC();
    const run_l1_entropy_tests = b.addRunArtifact(l1_entropy_tests);

    // L1 Prekey tests (Phase 2C)
    const l1_prekey_tests = b.addTest(.{
        .root_module = l1_prekey_mod,
    });
    const run_l1_prekey_tests = b.addRunArtifact(l1_prekey_tests);

    // L1 DID tests (Phase 2D)
    const l1_did_tests = b.addTest(.{
        .root_module = l1_did_mod,
    });
    const run_l1_did_tests = b.addRunArtifact(l1_did_tests);

    // ========================================================================
    // L1 PQXDH tests (Phase 3)
    // ========================================================================
    const l1_pqxdh_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/pqxdh.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_pqxdh_mod.addIncludePath(b.path("vendor/liboqs/install/include"));
    l1_pqxdh_mod.addLibraryPath(b.path("vendor/liboqs/install/lib"));
    l1_pqxdh_mod.linkSystemLibrary("oqs", .{ .needed = true });
    // Consuming artifacts must linkLibC()

    // Import PQXDH into main L1 module
    l1_mod.addImport("pqxdh", l1_pqxdh_mod);

    // Tests (root is test_pqxdh.zig)
    const l1_pqxdh_tests_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/test_pqxdh.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Tests import the library module 'pqxdh' (relative import works too, but module is cleaner if we use @import("pqxdh"))
    // But test_pqxdh.zig uses @import("pqxdh.zig") which is relative file import.
    // If we use relative import, the test module must be able to resolve pqxdh.zig.
    // Since they are in same dir, relative import works.
    // BUT the artifact compiled from test_pqxdh.zig needs to link liboqs because it effectively includes pqxdh.zig code.

    const l1_pqxdh_tests = b.addTest(.{
        .root_module = l1_pqxdh_tests_mod,
    });
    l1_pqxdh_tests.linkLibC();
    l1_pqxdh_tests.addIncludePath(b.path("vendor/liboqs/install/include"));
    l1_pqxdh_tests.addLibraryPath(b.path("vendor/liboqs/install/lib"));
    l1_pqxdh_tests.linkSystemLibrary("oqs");
    const run_l1_pqxdh_tests = b.addRunArtifact(l1_pqxdh_tests);

    // Link time module to l1_vector_mod
    // ========================================================================
    // Time Module (L0)
    // ========================================================================
    const time_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/time.zig"),
        .target = target,
        .optimize = optimize,
    });

    // L1 Vector tests (Phase 3C)
    const l1_vector_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/vector.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_vector_mod.addImport("time", time_mod);

    const l1_vector_tests = b.addTest(.{
        .root_module = l1_vector_mod,
    });
    // Add Argon2 support for vector tests (via entropy.zig)
    l1_vector_tests.addCSourceFiles(.{
        .files = &.{
            "vendor/argon2/src/argon2.c",
            "vendor/argon2/src/core.c",
            "vendor/argon2/src/blake2/blake2b.c",
            "vendor/argon2/src/thread.c",
            "vendor/argon2/src/encoding.c",
            "vendor/argon2/src/opt.c",
        },
        .flags = &.{
            "-std=c99",
            "-O3",
            "-fPIC",
            "-DHAVE_PTHREAD",
        },
    });
    l1_vector_tests.addIncludePath(b.path("vendor/argon2/include"));
    l1_vector_tests.linkLibC();
    const run_l1_vector_tests = b.addRunArtifact(l1_vector_tests);

    // NOTE: Phase 3 PQXDH uses stubbed ML-KEM. Real liboqs integration pending.

    // Test step (runs Phase 2B + 2C + 2D + 3C SDK tests)
    const test_step = b.step("test", "Run SDK tests");
    test_step.dependOn(&run_crypto_tests.step);
    test_step.dependOn(&run_crypto_ffi_tests.step);
    test_step.dependOn(&run_l0_tests.step);
    test_step.dependOn(&run_l1_soulkey_tests.step);
    test_step.dependOn(&run_l1_entropy_tests.step);
    test_step.dependOn(&run_l1_prekey_tests.step);
    test_step.dependOn(&run_l1_did_tests.step);
    test_step.dependOn(&run_l1_vector_tests.step);
    test_step.dependOn(&run_l1_pqxdh_tests.step);

    // ========================================================================
    // Examples
    // ========================================================================

    // Example: LWF frame usage
    const lwf_example_mod = b.createModule(.{
        .root_source_file = b.path("examples/lwf_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    lwf_example_mod.addImport("../l0-transport/lwf.zig", l0_mod);

    const lwf_example = b.addExecutable(.{
        .name = "lwf_example",
        .root_module = lwf_example_mod,
    });
    b.installArtifact(lwf_example);

    // Example: Encryption usage
    const crypto_example_mod = b.createModule(.{
        .root_source_file = b.path("examples/crypto_example.zig"),
        .target = target,
        .optimize = optimize,
    });
    crypto_example_mod.addImport("../l1-identity/crypto.zig", l1_mod);

    const crypto_example = b.addExecutable(.{
        .name = "crypto_example",
        .root_module = crypto_example_mod,
    });
    b.installArtifact(crypto_example);

    // Examples step
    const examples_step = b.step("examples", "Build example programs");
    examples_step.dependOn(&b.addInstallArtifact(lwf_example, .{}).step);
    examples_step.dependOn(&b.addInstallArtifact(crypto_example, .{}).step);

    // ========================================================================
    // Convenience Commands
    // ========================================================================

    // Run LWF example
    const run_lwf_example = b.addRunArtifact(lwf_example);
    const run_lwf_step = b.step("run-lwf", "Run LWF frame example");
    run_lwf_step.dependOn(&run_lwf_example.step);

    // Run crypto example
    const run_crypto_example = b.addRunArtifact(crypto_example);
    const run_crypto_step = b.step("run-crypto", "Run encryption example");
    run_crypto_step.dependOn(&run_crypto_example.step);
}
