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
    c.linkLibCpp();
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

    const tracy = blk: {
        const ret = b.addModule("tracy", .{
            .root_source_file = b.path("lib/tracy/root.zig"),
            .target = target,
            .optimize = optimize,
            .sanitize_c = false, // tracy stores bad enum values
        });

        ret.addCSourceFiles(.{
            .root = b.path("thirdparty/tracy/public/"),
            .files = &.{
                "TracyClient.cpp",
            },
            .flags = &.{
                "-DTRACY_ENABLE",
                // "-DTRACY_SYMBOL_OFFLINE_RESOLVE",
            },
        });

        ret.addIncludePath(b.path("thirdparty/tracy/public"));
        ret.link_libc = true;
        ret.link_libcpp = true;

        break :blk ret;
    };

    const dyn = b.addModule("dyn", .{
        .root_source_file = b.path("lib/dyn/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // don't ask
    const sgr = b.addModule("sgr", .{
        .root_source_file = b.path("lib/sgr/root.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const qov = blk: {
        const module = b.addModule("qov", .{
            .root_source_file = b.path("lib/qov/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("core", core);
        module.addImport("wgm", wgm);

        break :blk module;
    };

    const svo = blk: {
        const module = b.addModule("svo", .{
            .root_source_file = b.path("lib/svo/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("core", core);
        module.addImport("qov", qov);
        module.addImport("wgm", wgm);

        break :blk module;
    };

    const obj = blk: {
        const module = b.addModule("obj", .{
            .root_source_file = b.path("lib/obj/root.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("core", core);
        module.addImport("wgm", wgm);
        module.addImport("qov", qov);

        break :blk module;
    };

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

    const ToBuild = packed struct {
        tracer: bool,
        voxeliser_sw: bool,
        voxeliser_hw: bool,
        svo_builder: bool,
        tracer_tests: bool,
        voxeliser_tests: bool,
        lib_tests: bool,
    };

    const to_build: ToBuild = .{
        //.tracer = optimize == .Debug,
        .tracer = true,
        .voxeliser_sw = true,
        .voxeliser_hw = true,
        .svo_builder = true,
        .tracer_tests = optimize == .Debug,
        .voxeliser_tests = true,
        .lib_tests = true,
    };

    if (to_build.svo_builder) {
        const exe = b.addExecutable(.{
            .name = "svo_builder",
            .root_source_file = b.path("voxeliser/svo_builder.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("qov", qov);
        exe.root_module.addImport("svo", svo);
        exe.root_module.addImport("wgm", wgm);

        b.installArtifact(exe);
    }

    if (to_build.voxeliser_sw) {
        const exe = b.addExecutable(.{
            .name = "voxeliser_sw",
            .root_source_file = b.path("voxeliser/software.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("qov", qov);
        exe.root_module.addImport("obj", obj);
        exe.root_module.addImport("wgm", wgm);

        b.installArtifact(exe);
    }

    if (to_build.voxeliser_hw) {
        const exe = b.addExecutable(.{
            .name = "voxeliser_hw",
            .root_source_file = b.path("voxeliser/hardware.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("gfx", gfx);
        exe.root_module.addImport("qov", qov);
        exe.root_module.addImport("obj", obj);
        exe.root_module.addImport("wgm", wgm);

        add_include_paths_for_zls(b, exe);

        b.installArtifact(exe);
    }

    if (to_build.tracer) {
        const exe = b.addExecutable(.{
            .name = "vktest",
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("dyn", dyn);
        exe.root_module.addImport("gfx", gfx);
        exe.root_module.addImport("imgui", imgui);
        exe.root_module.addImport("obj", obj);
        exe.root_module.addImport("qoi", qoi);
        exe.root_module.addImport("qov", qov);
        exe.root_module.addImport("svo", svo);
        exe.root_module.addImport("tracy", tracy);
        exe.root_module.addImport("wgm", wgm);
        // link_to_wgpu_and_sdl(b, exe);

        exe.root_module.addImport("mustache", mustache_module);

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

    if (to_build.voxeliser_tests) {
        const tests = b.addTest(.{
            .root_source_file = b.path("voxeliser/software.zig"),
            .test_runner = b.path("test_runner.zig"),
            .target = target,
            .optimize = optimize,
        });

        tests.root_module.addImport("sgr", sgr);

        tests.root_module.addImport("core", core);
        tests.root_module.addImport("qov", qov);
        tests.root_module.addImport("wgm", wgm);

        var run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;

        test_step.dependOn(&run_tests.step);
    }

    if (to_build.tracer_tests) {
        const exe_tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .test_runner = b.path("test_runner.zig"),
            .target = target,
            .optimize = optimize,
        });

        exe_tests.root_module.addImport("sgr", sgr);

        exe_tests.root_module.addImport("core", core);
        exe_tests.root_module.addImport("dyn", dyn);
        exe_tests.root_module.addImport("gfx", gfx);
        exe_tests.root_module.addImport("imgui", imgui);
        exe_tests.root_module.addImport("obj", obj);
        exe_tests.root_module.addImport("qoi", qoi);
        exe_tests.root_module.addImport("qov", qov);
        exe_tests.root_module.addImport("svo", svo);
        exe_tests.root_module.addImport("tracy", tracy);
        exe_tests.root_module.addImport("wgm", wgm);
        // link_to_wgpu_and_sdl(b, exe_tests);

        exe_tests.root_module.addImport("mustache", mustache_module);

        var run_exe_tests = b.addRunArtifact(exe_tests);
        run_exe_tests.has_side_effects = true;

        test_step.dependOn(&run_exe_tests.step);
    }

    const lib_list = .{
        .{ "core", core },
        .{ "dyn", dyn },
        .{ "gfx", gfx },
        .{ "imgui", imgui },
        .{ "qoi", qoi },
        .{ "qov", qov },
        .{ "sgr", sgr },
        .{ "tracy", tracy },
        .{ "wgm", wgm },
        .{ "svo", svo },
    };

    if (to_build.lib_tests) inline for (lib_list) |lib_tuple| {
        const lib_name = lib_tuple.@"0";

        const tests = b.addTest(.{
            .root_source_file = b.path(std.fmt.comptimePrint("lib/{s}/root.zig", .{lib_name})),
            .test_runner = if (!std.mem.eql(u8, lib_name, "sgr")) b.path("test_runner.zig") else null,
            .target = target,
            .optimize = optimize,
        });

        inline for (lib_list) |pair| if (!std.mem.eql(u8, lib_name, pair.@"0")) {
            tests.root_module.addImport(pair.@"0", pair.@"1");
        };

        var run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;

        test_step.dependOn(&run_tests.step);
    };
}
