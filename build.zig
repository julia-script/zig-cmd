const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const test_filter = b.option([]const u8, "test-filter", "Run tests with filter");

    const expect_lib = b.dependency("expect", .{
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("cmd", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const expect_module = expect_lib.module("expect");
    const lib = b.addStaticLibrary(.{
        .name = "zig-cmd",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("expect", expect_module);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .filter = test_filter,
    });

    lib_unit_tests.root_module.addImport("expect", expect_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    b.installArtifact(lib);
}
