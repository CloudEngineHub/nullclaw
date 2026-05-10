const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const compat_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/compat.zig"),
    });

    const websocket_module = b.addModule("websocket", .{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/websocket.zig"),
    });
    websocket_module.addImport("compat", compat_module);

    {
        const options = b.addOptions();
        options.addOption(bool, "websocket_blocking", false);
        websocket_module.addOptions("build", options);
    }

    {
        // run tests
        const tests = b.addTest(.{
            .root_module = websocket_module,
            .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
        });
        tests.root_module.link_libc = true;
        tests.root_module.addImport("compat", compat_module);
        const force_blocking = b.option(bool, "force_blocking", "Force blocking mode") orelse false;
        const options = b.addOptions();
        options.addOption(bool, "websocket_blocking", force_blocking);
        tests.root_module.addOptions("build", options);

        const run_test = b.addRunArtifact(tests);

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&run_test.step);
    }
}
