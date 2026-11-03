const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module: everything that can be tested without a socket.
    const lib_mod = b.addModule("learn_zig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // The server executable imports the library module by name.
    const exe = b.addExecutable(.{
        .name = "learn-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "learn_zig", .module = lib_mod },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the HTTP server");
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{ .root_module = lib_mod });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    // The README's code samples live in examples/ and run as tests too, so a
    // compiler upgrade that breaks a sample breaks CI.
    const examples_step = b.step("examples", "Run the README code samples");
    const examples = [_][]const u8{
        "examples/stage1_basics.zig",
        "examples/stage2_data.zig",
        "examples/stage3_memory.zig",
        "examples/stage4_io.zig",
        "examples/stage5_reader.zig",
    };
    for (examples) |path| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        }) });
        const run = b.addRunArtifact(t);
        examples_step.dependOn(&run.step);
        test_step.dependOn(&run.step);
    }
}
