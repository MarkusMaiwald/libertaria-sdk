const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const vaxis_dep = b.dependency("vaxis", .{});
    const vaxis_mod = vaxis_dep.module("vaxis");

    // ========================================================================
    // Time Module (L0)
    // ========================================================================
    const time_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/time.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // L0: Transport Layer
    // ========================================================================
    const l0_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    const ipc_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/ipc/client.zig"),
        .target = target,
        .optimize = optimize,
    });

    const utcp_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/utcp/socket.zig"),
        .target = target,
        .optimize = optimize,
    });
    utcp_mod.addImport("ipc", ipc_mod);
    utcp_mod.addImport("lwf", l0_mod);

    const opq_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/opq.zig"),
        .target = target,
        .optimize = optimize,
    });
    opq_mod.addImport("lwf", l0_mod);

    const l0_service_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/service.zig"),
        .target = target,
        .optimize = optimize,
    });
    l0_service_mod.addImport("lwf", l0_mod);
    l0_service_mod.addImport("utcp", utcp_mod);
    l0_service_mod.addImport("opq", opq_mod);

    const dht_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/dht.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gateway_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/gateway.zig"),
        .target = target,
        .optimize = optimize,
    });
    gateway_mod.addImport("dht", dht_mod);

    const relay_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/relay.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RFC-0015: Transport Skins (MIMIC_DNS for DPI evasion)
    const mimic_dns_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/mimic_dns.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RFC-0015: MIMIC_HTTPS with Domain Fronting
    const mimic_https_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/mimic_https.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RFC-0015: MIMIC_QUIC (HTTP/3 over QUIC)
    const mimic_quic_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/mimic_quic.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bridge_mod = b.createModule(.{
        .root_source_file = b.path("l2-federation/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });

    const l2_policy_mod = b.createModule(.{
        .root_source_file = b.path("l2-membrane/policy.zig"),
        .target = target,
        .optimize = optimize,
    });
    l2_policy_mod.addImport("lwf", l0_mod);

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
        .root_source_file = b.path("l1-identity/mod.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add crypto modules as imports to L1
    l1_mod.addImport("shake", crypto_shake_mod);
    l1_mod.addImport("fips202_bridge", crypto_fips202_mod);

    // ========================================================================
    // L1 PQXDH Module (Phase 3) - Core Dependency
    // ========================================================================
    const l1_pqxdh_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/pqxdh.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_pqxdh_mod.addIncludePath(b.path("vendor/liboqs/install/include"));
    l1_pqxdh_mod.addLibraryPath(b.path("vendor/liboqs/install/lib"));
    l1_pqxdh_mod.linkSystemLibrary("oqs", .{ .needed = true });

    // Ensure l1_mod uses PQXDH
    l1_mod.addImport("pqxdh", l1_pqxdh_mod);

    // ========================================================================
    // L1 Modules: SoulKey, Entropy, Prekey (Phase 2B + 2C)
    // ========================================================================
    const l1_soulkey_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/soulkey.zig"),
        .target = target,
        .optimize = optimize,
    });
    // SoulKey needs PQXDH for deterministic generation
    l1_soulkey_mod.addImport("pqxdh", l1_pqxdh_mod);

    const l1_entropy_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/entropy.zig"),
        .target = target,
        .optimize = optimize,
    });

    // UTCP needs entropy for fast validation
    utcp_mod.addImport("entropy", l1_entropy_mod);

    const l1_prekey_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/prekey.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_prekey_mod.addImport("pqxdh", l1_pqxdh_mod);

    const l1_did_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/did.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_did_mod.addImport("pqxdh", l1_pqxdh_mod);

    // ========================================================================
    // L1 Slash Protocol & L0 Quarantine
    // ========================================================================
    const l1_slash_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/slash.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_mod.addImport("slash", l1_slash_mod);

    const l0_quarantine_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/quarantine.zig"),
        .target = target,
        .optimize = optimize,
    });
    utcp_mod.addImport("quarantine", l0_quarantine_mod);
    l0_service_mod.addImport("quarantine", l0_quarantine_mod);

    // ========================================================================
    // L1 Trust Graph Module (Core Dependency for QVL/PoP)
    // ========================================================================
    const l1_trust_graph_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/trust_graph.zig"),
        .target = target,
        .optimize = optimize,
    });
    // trust_graph needs crypto types
    l1_trust_graph_mod.addImport("crypto", l1_mod);

    // ========================================================================
    // L1 Proof of Path Module (PoP)
    // ========================================================================
    const l1_pop_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/proof_of_path.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_pop_mod.addImport("trust_graph", l1_trust_graph_mod);
    l1_pop_mod.addImport("time", time_mod);
    l1_pop_mod.addImport("soulkey", l1_soulkey_mod);

    // ========================================================================
    // L1 QVL (Quasar Vector Lattice) - Advanced Graph Engine
    // ========================================================================
    const l1_qvl_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/qvl.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_qvl_mod.addImport("trust_graph", l1_trust_graph_mod);
    l1_qvl_mod.addImport("proof_of_path", l1_pop_mod);
    l1_qvl_mod.addImport("time", time_mod);
    // Note: libmdbx linking removed - using stub implementation for now
    // TODO: Add real libmdbx when available on build system

    // QVL FFI (C ABI exports for L2 integration)
    const l1_qvl_ffi_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/qvl_ffi.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_qvl_ffi_mod.addImport("qvl", l1_qvl_mod);
    l1_qvl_ffi_mod.addImport("slash", l1_slash_mod);
    l1_qvl_ffi_mod.addImport("time", time_mod);
    l1_qvl_ffi_mod.addImport("trust_graph", l1_trust_graph_mod);

    // QVL FFI static library (for Rust L2 Membrane Agent)
    const qvl_ffi_lib = b.addLibrary(.{
        .name = "qvl_ffi",
        .root_module = l1_qvl_ffi_mod,
        .linkage = .static,
    });
    qvl_ffi_lib.linkLibC();
    b.installArtifact(qvl_ffi_lib);

    // ========================================================================
    // L4 Feed — Temporal Event Store
    // ========================================================================
    const l4_feed_mod = b.createModule(.{
        .root_source_file = b.path("l4-feed/feed.zig"),
        .target = target,
        .optimize = optimize,
    });

    // L4 Feed tests (requires libduckdb at runtime)
    const l4_feed_tests = b.addTest(.{
        .root_module = l4_feed_mod,
    });
    l4_feed_tests.linkLibC(); // Required for DuckDB C API
    const run_l4_feed_tests = b.addRunArtifact(l4_feed_tests);

    // ========================================================================
    // RFC-0015: Transport Skins (DPI Resistance)
    // ========================================================================
    const png_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/png.zig"),
        .target = target,
        .optimize = optimize,
    });

    const transport_skins_mod = b.createModule(.{
        .root_source_file = b.path("l0-transport/transport_skins.zig"),
        .target = target,
        .optimize = optimize,
    });
    transport_skins_mod.addImport("png", png_mod);
    transport_skins_mod.addImport("mimic_dns", mimic_dns_mod);
    transport_skins_mod.addImport("mimic_https", mimic_https_mod);
    transport_skins_mod.addImport("mimic_quic", mimic_quic_mod);

    // Transport Skins tests
    const png_tests = b.addTest(.{
        .root_module = png_mod,
    });
    const run_png_tests = b.addRunArtifact(png_tests);

    const transport_skins_tests = b.addTest(.{
        .root_module = transport_skins_mod,
    });
    const run_transport_skins_tests = b.addRunArtifact(transport_skins_tests);

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

    // UTCP tests
    const utcp_tests = b.addTest(.{
        .root_module = utcp_mod,
    });
    const run_utcp_tests = b.addRunArtifact(utcp_tests);

    // L2 Policy tests
    const l2_policy_tests = b.addTest(.{
        .root_module = l2_policy_mod,
    });
    const run_l2_policy_tests = b.addRunArtifact(l2_policy_tests);

    // OPQ tests
    const opq_tests = b.addTest(.{
        .root_module = opq_mod,
    });
    const run_opq_tests = b.addRunArtifact(opq_tests);

    // L0 Service tests
    const l0_service_tests = b.addTest(.{
        .root_module = l0_service_mod,
    });
    const run_l0_service_tests = b.addRunArtifact(l0_service_tests);

    // DHT tests
    const dht_tests = b.addTest(.{
        .root_module = dht_mod,
    });
    const run_dht_tests = b.addRunArtifact(dht_tests);

    // Gateway tests
    const gateway_tests = b.addTest(.{
        .root_module = gateway_mod,
    });
    const run_gateway_tests = b.addRunArtifact(gateway_tests);

    // Relay tests
    const relay_tests = b.addTest(.{
        .root_module = relay_mod,
    });
    const run_relay_tests = b.addRunArtifact(relay_tests);

    // Bridge tests
    const bridge_tests = b.addTest(.{
        .root_module = bridge_mod,
    });
    const run_bridge_tests = b.addRunArtifact(bridge_tests);

    // L1 SoulKey tests (Phase 2B)
    const l1_soulkey_tests = b.addTest(.{
        .root_module = l1_soulkey_mod,
    });
    // Tests linking liboqs effectively happen via the module now, but we also link LibC
    l1_soulkey_tests.linkLibC();
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
    l1_prekey_tests.linkLibC();
    const run_l1_prekey_tests = b.addRunArtifact(l1_prekey_tests);

    // L1 DID tests (Phase 2D)
    const l1_did_tests = b.addTest(.{
        .root_module = l1_did_mod,
    });
    l1_did_tests.linkLibC();
    const run_l1_did_tests = b.addRunArtifact(l1_did_tests);

    // L1 Slash tests
    const l1_slash_tests = b.addTest(.{
        .root_module = l1_slash_mod,
    });
    l1_slash_tests.linkLibC();
    const run_l1_slash_tests = b.addRunArtifact(l1_slash_tests);

    // L0 Quarantine tests
    const l0_quarantine_tests = b.addTest(.{
        .root_module = l0_quarantine_mod,
    });
    const run_l0_quarantine_tests = b.addRunArtifact(l0_quarantine_tests);

    // Import PQXDH into main L1 module
    // Tests (root is test_pqxdh.zig)
    const l1_pqxdh_tests_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/test_pqxdh.zig"),
        .target = target,
        .optimize = optimize,
    });

    const l1_pqxdh_tests = b.addTest(.{
        .root_module = l1_pqxdh_tests_mod,
    });
    l1_pqxdh_tests.linkLibC();
    l1_pqxdh_tests.addIncludePath(b.path("vendor/liboqs/install/include"));
    l1_pqxdh_tests.addLibraryPath(b.path("vendor/liboqs/install/lib"));
    l1_pqxdh_tests.linkSystemLibrary("oqs");
    const run_l1_pqxdh_tests = b.addRunArtifact(l1_pqxdh_tests);

    // L1 Vector tests (Phase 3C)
    const l1_vector_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/vector.zig"),
        .target = target,
        .optimize = optimize,
    });
    l1_vector_mod.addImport("time", time_mod);
    l1_vector_mod.addImport("pqxdh", l1_pqxdh_mod);
    l1_vector_mod.addImport("trust_graph", l1_trust_graph_mod);
    l1_vector_mod.addImport("soulkey", l1_soulkey_mod);

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

    // L1 QVL tests
    const l1_qvl_tests = b.addTest(.{
        .root_module = l1_qvl_mod,
    });
    const run_l1_qvl_tests = b.addRunArtifact(l1_qvl_tests);

    // L1 QVL FFI tests (C ABI validation)
    const l1_qvl_ffi_tests = b.addTest(.{
        .root_module = l1_qvl_ffi_mod,
    });
    l1_qvl_ffi_tests.linkLibC(); // Required for C allocator
    const run_l1_qvl_ffi_tests = b.addRunArtifact(l1_qvl_ffi_tests);

    // NOTE: C test harness (test_qvl_ffi.c) can be compiled manually:
    // zig cc -I. l1-identity/test_qvl_ffi.c zig-out/lib/libqvl_ffi.a -o test_qvl_ffi

    // Test step (runs Phase 2B + 2C + 2D + 3C SDK tests)
    const test_step = b.step("test", "Run SDK tests");
    test_step.dependOn(&run_crypto_tests.step);
    test_step.dependOn(&run_crypto_ffi_tests.step);
    test_step.dependOn(&run_l0_tests.step);
    test_step.dependOn(&run_l1_soulkey_tests.step);
    test_step.dependOn(&run_l1_entropy_tests.step);
    test_step.dependOn(&run_l1_prekey_tests.step);
    test_step.dependOn(&run_l1_did_tests.step);
    test_step.dependOn(&run_l1_slash_tests.step);
    test_step.dependOn(&run_l0_quarantine_tests.step);
    test_step.dependOn(&run_l1_vector_tests.step);
    test_step.dependOn(&run_l1_pqxdh_tests.step);
    test_step.dependOn(&run_utcp_tests.step);
    test_step.dependOn(&run_opq_tests.step);
    test_step.dependOn(&run_l0_service_tests.step);
    test_step.dependOn(&run_dht_tests.step);
    test_step.dependOn(&run_gateway_tests.step);
    test_step.dependOn(&run_relay_tests.step);
    test_step.dependOn(&run_bridge_tests.step);
    test_step.dependOn(&run_l1_qvl_tests.step);
    test_step.dependOn(&run_l1_qvl_ffi_tests.step);
    test_step.dependOn(&run_l2_policy_tests.step);
    test_step.dependOn(&run_l4_feed_tests.step);
    test_step.dependOn(&run_png_tests.step);
    test_step.dependOn(&run_transport_skins_tests.step);

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

    // Run crypto example
    const run_crypto_example = b.addRunArtifact(crypto_example);
    const run_crypto_step = b.step("run-crypto", "Run encryption example");
    run_crypto_step.dependOn(&run_crypto_example.step);

    // ========================================================================
    // Capsule Core (Phase 10) Reference Implementation
    // ========================================================================
    const capsule_control_mod = b.createModule(.{
        .root_source_file = b.path("capsule-core/src/control.zig"),
        .target = target,
        .optimize = optimize,
    });
    capsule_control_mod.addImport("qvl", l1_qvl_mod);

    const capsule_mod = b.createModule(.{
        .root_source_file = b.path("capsule-core/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link L0 (Transport)
    capsule_mod.addImport("l0_transport", l0_mod);
    capsule_mod.addImport("utcp", utcp_mod);

    // Link L1 (Identity)
    capsule_mod.addImport("l1_identity", l1_mod);
    capsule_mod.addImport("qvl", l1_qvl_mod);
    capsule_mod.addImport("dht", dht_mod);
    capsule_mod.addImport("gateway", gateway_mod);
    capsule_mod.addImport("relay", relay_mod);
    capsule_mod.addImport("quarantine", l0_quarantine_mod);
    capsule_mod.addImport("policy", l2_policy_mod);
    capsule_mod.addImport("soulkey", l1_soulkey_mod);
    capsule_mod.addImport("vaxis", vaxis_mod);
    capsule_mod.addImport("control", capsule_control_mod);

    const capsule_exe = b.addExecutable(.{
        .name = "capsule",
        .root_module = capsule_mod,
    });
    // Link LibC (required for Argon2/OQS via L1)
    capsule_exe.linkLibC();
    // Link SQLite3 (required for Persistent State)
    capsule_exe.linkSystemLibrary("sqlite3");
    // Link DuckDB (required for Analytical QVL)
    capsule_exe.linkSystemLibrary("duckdb");

    b.installArtifact(capsule_exe);

    // Run command: zig build run -- args
    const run_capsule = b.addRunArtifact(capsule_exe);
    if (b.args) |args| {
        run_capsule.addArgs(args);
    }
    const run_step = b.step("run", "Run the Capsule Node");
    run_step.dependOn(&run_capsule.step);
}
