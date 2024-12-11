const std = @import("std");

const test_targets = [_]std.Target.Query{
    .{}, // native
};

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "generate-amf-structs",
        .root_source_file = b.path("tools/generate-amf-types.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    exe.linkSystemLibrary("yaml");
    exe.linkLibC();

    const test_step = b.step("test", "Run unit tests");

    for (test_targets) |target| {
        const unit_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.resolveTargetQuery(target),
        });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        run_unit_tests.has_side_effects = true;
        test_step.dependOn(&run_unit_tests.step);
    }
}
