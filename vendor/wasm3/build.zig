const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "wasm3",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    lib.root_module.addIncludePath(b.path("source"));
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_bind.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_code.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_compile.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_core.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_env.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_exec.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_function.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_info.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_module.c") });
    lib.root_module.addCSourceFile(.{ .file = b.path("source/m3_parse.c") });

    b.installArtifact(lib);
}
