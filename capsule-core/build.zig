const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Modules
    const ipc = b.createModule(.{
        .root_source_file = b.path("../l0-transport/ipc/client.zig"),
    });
    const entropy = b.createModule(.{
        .root_source_file = b.path("../l1-identity/entropy.zig"),
    });
    const quarantine = b.createModule(.{
        .root_source_file = b.path("../l0-transport/quarantine.zig"),
    });
    const shake = b.createModule(.{
        .root_source_file = b.path("../src/crypto/shake.zig"),
    });
    const fips202_bridge = b.createModule(.{
        .root_source_file = b.path("../src/crypto/fips202_bridge.zig"),
    });
    const pqxdh = b.createModule(.{
        .root_source_file = b.path("../l1-identity/pqxdh.zig"),
    });
    const slash = b.createModule(.{
        .root_source_file = b.path("../l1-identity/slash.zig"),
        .imports = &.{
            .{ .name = "crypto", .module = b.createModule(.{ .root_source_file = b.path("../l1-identity/crypto.zig") }) },
        },
    });

    const time = b.createModule(.{
        .root_source_file = b.path("../l0-transport/time.zig"),
    });
    const trust_graph = b.createModule(.{
        .root_source_file = b.path("../l1-identity/trust_graph.zig"),
    });
    const crypto = b.createModule(.{
        .root_source_file = b.path("../l1-identity/crypto.zig"),
        .imports = &.{
            .{ .name = "trust_graph", .module = trust_graph },
            .{ .name = "time", .module = time },
        },
    });

    const lwf = b.createModule(.{
        .root_source_file = b.path("../l0-transport/lwf.zig"),
        .imports = &.{
            .{ .name = "ipc", .module = ipc },
            .{ .name = "entropy", .module = entropy },
            .{ .name = "quarantine", .module = quarantine },
        },
    });

    const utcp = b.createModule(.{
        .root_source_file = b.path("../l0-transport/utcp/socket.zig"),
        .imports = &.{
            .{ .name = "shake", .module = shake },
            .{ .name = "fips202_bridge", .module = fips202_bridge },
            .{ .name = "pqxdh", .module = pqxdh },
            .{ .name = "slash", .module = slash },
            .{ .name = "ipc", .module = ipc },
            .{ .name = "lwf", .module = lwf },
            .{ .name = "entropy", .module = entropy },
        },
    });

    const qvl = b.createModule(.{
        .root_source_file = b.path("../l1-identity/qvl.zig"),
        .imports = &.{
            .{ .name = "time", .module = time },
        },
    });

    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const vaxis_mod = vaxis_dep.module("vaxis");

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "capsule",
        .root_module = exe_mod,
    });

    exe.root_module.addImport("l0_transport", lwf); // Name mismatch? Step 4902 says l0_transport=lwf
    exe.root_module.addImport("utcp", utcp);
    exe.root_module.addImport("l1_identity", crypto); // Name mismatch? Step 4902 says l1_identity=crypto
    exe.root_module.addImport("qvl", qvl);
    exe.root_module.addImport("quarantine", quarantine);
    exe.root_module.addImport("vaxis", vaxis_mod);

    exe.linkSystemLibrary("sqlite3");
    exe.linkSystemLibrary("duckdb");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
