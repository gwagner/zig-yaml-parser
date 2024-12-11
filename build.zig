const std = @import("std");

const test_targets = [_]std.Target.Query{
    .{}, // native
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const lib = b.addStaticLibrary(.{
        .name = "yaml-parser",
        .root_source_file = b.path("src/main.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    lib.addIncludePath(b.path("src/"));
    lib.linkSystemLibrary("yaml");
    lib.linkLibC();

    b.installArtifact(lib);
}
