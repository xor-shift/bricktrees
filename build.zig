const std = @import("std");

const mustache = @import("thirdparty/mustache-zig/src/mustache.zig");

fn link_to_wgpu_and_sdl(b: *std.Build, c: *std.Build.Step.Compile) void {
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
    c.addIncludePath(b.path("thirdparty/SDL/include/"));
    c.addLibraryPath(b.path("thirdparty/SDL/build-debug/"));
    c.linkSystemLibrary("SDL3");
    c.addLibraryPath(b.path("thirdparty/wgpu-native/target/release/"));
    c.linkSystemLibrary("wgpu_native");
    c.linkLibC();
}

// fuck you, ZLS
fn add_include_paths_for_zls(b: *std.Build, to: anytype) void {
    to.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
    to.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
    to.addIncludePath(b.path("thirdparty/SDL/include/"));
    to.addLibraryPath(b.path("thirdparty/SDL/build-debug/"));
    to.addIncludePath(b.path("thirdparty/cimgui"));
    to.addIncludePath(b.path("thirdparty/cimgui/imgui"));
}

const ShaderBuildStep = struct {
    step: std.Build.Step,

    pub fn init(b: *std.Build, comptime out_filename: []const u8) *ShaderBuildStep {
        const ret = b.allocator.create(ShaderBuildStep) catch @panic("OOM");
        ret.* = .{
            .step = std.Build.Step.init(.{
                .name = "shader build step for " ++ out_filename,
                .owner = b,
                .id = .custom,
                .makeFn = ShaderBuildStep.make_fn,
            }),
        };

        return ret;
    }

    pub fn make_fn(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
        const self: *ShaderBuildStep = @fieldParentPtr("step", step);
        defer prog_node.end();

        _ = self;
        // TODO
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            // .cpu_model = .baseline,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        // .preferred_optimize_mode = .Debug,
    });

    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run unit tests");

    const cimgui_step = b.addSystemCommand(&.{
        "nu",
    });
    cimgui_step.addFileArg(b.path("scripts/generate_cimgui.nu"));
    cimgui_step.addDirectoryArg(b.path("thirdparty/cimgui/"));
    cimgui_step.addFileArg(b.path("lib/imgui/imconfig.h"));
    const cimgui_dir = cimgui_step.addOutputDirectoryArg("cimgui");

    const mustache_module = b.addModule("mustache", .{
        .root_source_file = b.path("thirdparty/mustache-zig/src/mustache.zig"),
        .target = target,
        .optimize = optimize,
    });

    const scene_config_module = b.addModule("scene_config", .{
        .root_source_file = b.path("config.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tracy = blk: {
        const ret = b.addModule("tracy", .{
            .root_source_file = b.path("lib/tracy/root.zig"),
            .target = target,
            .optimize = optimize,
        });

        ret.addCSourceFiles(.{
            .root = b.path("thirdparty/tracy/public/"),
            .files = &.{
                "TracyClient.cpp",
            },
            .flags = &.{
                "-DTRACY_ENABLE",
            },
        });

        ret.addIncludePath(b.path("thirdparty/tracy/public"));

        break :blk ret;
    };

    const core = b.addModule("core", .{
        .root_source_file = b.path("lib/core/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const qoi = b.addModule("qoi", .{
        .root_source_file = b.path("lib/qoi/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const wgm = b.addModule("wgm", .{
        .root_source_file = b.path("lib/wgm/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const gfx = blk: {
        const gfx = b.addModule("gfx", .{
            .root_source_file = b.path("lib/gfx/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });

        gfx.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
        gfx.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
        gfx.addIncludePath(b.path("thirdparty/SDL/include/"));
        gfx.addLibraryPath(b.path("thirdparty/SDL/build-debug/"));
        gfx.linkSystemLibrary("SDL3", .{ .needed = true });
        gfx.addLibraryPath(b.path("thirdparty/wgpu-native/target/release/"));
        gfx.linkSystemLibrary("wgpu_native", .{ .needed = true });

        break :blk gfx;
    };

    const imgui = blk: {
        var imgui = b.addModule("imgui", .{
            .root_source_file = b.path("lib/imgui/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        });

        const c_flags = &.{
            "-DIMGUI_USER_CONFIG=\"../imconfig.h\"",
        };

        imgui.addCSourceFiles(.{
            .root = b.path("thirdparty/cimgui/"),
            .files = &.{
                "imgui/imgui.cpp",
                "imgui/imgui_draw.cpp",
                "imgui/imgui_demo.cpp",
                "imgui/imgui_widgets.cpp",

                "imgui/imgui_tables.cpp",

                "imgui/misc/freetype/imgui_freetype.cpp",
            },
            .flags = c_flags,
        });

        imgui.addCSourceFile(.{
            .file = cimgui_dir.path(b, "cimgui.cpp"),
            .flags = c_flags,
        });

        imgui.addIncludePath(cimgui_dir);
        imgui.addIncludePath(cimgui_dir.path(b, "imgui"));

        imgui.linkSystemLibrary("freetype", .{ .needed = true });

        imgui.addImport("gfx", gfx);

        break :blk imgui;
    };

    // executable
    {
        const exe = b.addExecutable(.{
            .name = "vktest",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("tracy", tracy);
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("qoi", qoi);
        exe.root_module.addImport("wgm", wgm);
        exe.root_module.addImport("imgui", imgui);
        exe.root_module.addImport("gfx", gfx);
        // link_to_wgpu_and_sdl(b, exe);

        exe.root_module.addImport("mustache", mustache_module);

        exe.root_module.addImport("scene_config", scene_config_module);

        add_include_paths_for_zls(b, exe);

        b.installArtifact(exe);

        var run_cmd = b.addRunArtifact(exe);

        run_cmd.step.dependOn(b.getInstallStep());
        run_cmd.cwd = b.path("run");

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        run_step.dependOn(&run_cmd.step);
    }

    // executable's tests
    {
        const exe_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .test_runner = b.path("test_runner.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_tests.root_module.addImport("tracy", tracy);
        exe_tests.root_module.addImport("core", core);
        exe_tests.root_module.addImport("qoi", qoi);
        exe_tests.root_module.addImport("wgm", wgm);
        exe_tests.root_module.addImport("imgui", imgui);
        // link_to_wgpu_and_sdl(b, exe_tests);

        exe_tests.root_module.addImport("scene_config", scene_config_module);

        var run_exe_tests = b.addRunArtifact(exe_tests);
        run_exe_tests.has_side_effects = true;

        test_step.dependOn(&run_exe_tests.step);
    }

    // basic tests
    inline for (.{ "core", "wgm", "qoi", "imgui" }) |lib_name| {
        const tests = b.addTest(.{
            .root_source_file = b.path(std.fmt.comptimePrint("lib/{s}/root.zig", .{lib_name})),
            .test_runner = if (!std.mem.eql(u8, lib_name, "core")) b.path("test_runner.zig") else null,
            .target = target,
            .optimize = optimize,
        });

        if (!std.mem.eql(u8, lib_name, "core")) {
            tests.root_module.addImport("core", core);
        }

        var run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;

        test_step.dependOn(&run_tests.step);
    }

    // inline for (library_names) |library_name| {
    // }
}
