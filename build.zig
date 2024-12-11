const std = @import("std");

const test_targets = [_]std.Target.Query{
    .{}, // native
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(b.getInstallStep());

    var tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
        .optimize = optimize,
    });
    tests.addIncludePath(b.path("src/"));
    tests.linkSystemLibrary("yaml");
    tests.linkLibC();
    test_step.dependOn(&b.addRunArtifact(tests).step);

    const lib = b.addStaticLibrary(.{
        .name = "yaml-parser",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    lib.addIncludePath(b.path("src/"));
    lib.linkSystemLibrary("yaml");
    lib.linkLibC();
    lib.step.dependOn(&tests.step);

    b.installArtifact(lib);
}
