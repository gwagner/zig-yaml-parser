const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(b.getInstallStep());
    var tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.addIncludePath(b.path("src/"));
    tests.linkSystemLibrary("yaml");
    tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const lib = b.addModule("yaml-parser", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib.addIncludePath(b.path("src/"));
    lib.linkSystemLibrary("yaml", .{});

    const compile = b.step("compile", "Compile the library");
    compile.dependOn(test_step);
}
