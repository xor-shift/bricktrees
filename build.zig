const std = @import("std");

fn add_c_stuff(b: *std.Build, c: *std.Build.Step.Compile) void {
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
    c.addIncludePath(b.path("thirdparty/SDL/include/"));
    c.addLibraryPath(b.path("thirdparty/SDL/build/"));
    c.linkSystemLibrary("SDL3");
    c.addLibraryPath(b.path("thirdparty/wgpu-native/target/debug/"));
    c.linkSystemLibrary("wgpu_native");
    c.linkLibC();
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const qoi = b.addStaticLibrary(.{
        .name = "qoi",
        .root_source_file = b.path("lib/sdl/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(qoi);

    const exe = b.addExecutable(.{
        .name = "vktest",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    add_c_stuff(b, exe);
    exe.linkLibrary(qoi);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    add_c_stuff(b, exe_unit_tests);
    exe_unit_tests.linkLibrary(qoi);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const qoi_unit_tests = b.addTest(.{
        .root_source_file = b.path("lib/qoi/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    qoi_unit_tests.linkLibrary(qoi);
    const run_qoi_unit_tests = b.addRunArtifact(qoi_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_qoi_unit_tests.step);
}
