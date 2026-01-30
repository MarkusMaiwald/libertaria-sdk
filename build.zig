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
    // L1: Identity & Crypto Layer
    // ========================================================================
    const l1_mod = b.createModule(.{
        .root_source_file = b.path("l1-identity/crypto.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ========================================================================
    // Tests
    // ========================================================================

    // L0 tests
    const l0_tests = b.addTest(.{
        .root_module = l0_mod,
    });
    const run_l0_tests = b.addRunArtifact(l0_tests);

    // L1 tests
    const l1_tests = b.addTest(.{
        .root_module = l1_mod,
    });
    const run_l1_tests = b.addRunArtifact(l1_tests);

    // Test step (runs all tests)
    const test_step = b.step("test", "Run all SDK tests");
    test_step.dependOn(&run_l0_tests.step);
    test_step.dependOn(&run_l1_tests.step);

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
