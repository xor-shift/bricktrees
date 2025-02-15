const std = @import("std");

const mustache = @import("thirdparty/mustache-zig/src/mustache.zig");

const scene_config = @import("config.zig");

fn link_to_wgpu_and_sdl(b: *std.Build, c: *std.Build.Step.Compile) void {
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
    c.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
    c.addIncludePath(b.path("thirdparty/SDL/include/"));
    c.addLibraryPath(b.path("thirdparty/SDL/build/"));
    c.linkSystemLibrary("SDL3");
    c.addLibraryPath(b.path("thirdparty/wgpu-native/target/debug/"));
    c.linkSystemLibrary("wgpu_native");
    c.linkLibC();
}

// fuck you, ZLS
fn add_include_paths_for_zls(b: *std.Build, to: anytype) void {
    to.addIncludePath(b.path("thirdparty/wgpu-native/ffi/webgpu-headers"));
    to.addIncludePath(b.path("thirdparty/wgpu-native/ffi/"));
    to.addIncludePath(b.path("thirdparty/SDL/include/"));
    to.addLibraryPath(b.path("thirdparty/SDL/build/"));
    to.addIncludePath(b.path("thirdparty/cimgui"));
    to.addIncludePath(b.path("thirdparty/cimgui/imgui"));
}

pub fn cimgui_make_fn(step: *std.Build.Step, prog_node: std.Progress.Node) anyerror!void {
    const cwd: std.fs.Dir = step.owner.build_root.handle;

    const files_to_back_up = .{
        "cimgui.cpp",
        "cimgui.h",
        "generator/output/definitions.json",
        "generator/output/definitions.lua",
        "generator/output/structs_and_enums.json",
        "generator/output/structs_and_enums.lua",
        "generator/output/typedefs_dict.json",
        "generator/output/typedefs_dict.lua",
    };

    {
        const node = prog_node.start("backup original files", files_to_back_up.len);
        defer node.end();

        inline for (files_to_back_up) |filename| {
            try cwd.rename(
                "thirdparty/cimgui/" ++ filename,
                "thirdparty/cimgui/" ++ filename ++ ".bak",
            );
            node.completeOne();
        }
    }

    defer {
        const node = prog_node.start("restore original files", files_to_back_up.len);
        defer node.end();

        inline for (files_to_back_up) |filename| {
            cwd.rename(
                "thirdparty/cimgui/" ++ filename ++ ".bak",
                "thirdparty/cimgui/" ++ filename,
            ) catch |e| {
                std.log.err("failed restoring {s}: {s}", .{
                    filename,
                    @errorName(e),
                });
            };

            node.completeOne();
        }

        // "preprocesed", lol
        cwd.deleteFile("thirdparty/cimgui/generator/preprocesed.h") catch |e| {
            std.log.err("failed removing a temporary file: {s}", .{
                @errorName(e),
            });
        };
    }

    {
        const node = prog_node.start("generate cimgui bindings", 1);
        defer node.end();

        const generator_dir = try cwd.openDir("thirdparty/cimgui/generator/", .{
            .iterate = false,
            .no_follow = true,
            .access_sub_paths = true,
        });

        const result = std.process.Child.run(.{
            .allocator = step.owner.allocator,
            .argv = &.{
                "luajit",
                "generator.lua",
                "gcc",
                "internal noimstrv",
                "-DIMGUI_USER_CONFIG=\"../../../lib/imgui/imconfig.h\"",
            },
            .cwd_dir = generator_dir,
        }) catch |e| {
            return step.fail("failed to spawn luajit: {any}", .{e});
        };

        switch (result.term) {
            .Exited => |exit_code| if (exit_code != 0) {
                return step.fail("luajit returned with non-zero exit code {d}", .{exit_code});
            },
            .Signal, .Stopped, .Unknown => {
                return step.fail("luajit exited unexpectedly", .{});
            },
        }
    }

    {
        const node = prog_node.start("copy files over", 2);
        defer node.end();

        try cwd.rename(
            "thirdparty/cimgui/cimgui.h",
            "lib/imgui/generated/cimgui.h",
        );
        node.completeOne();

        try cwd.rename(
            "thirdparty/cimgui/cimgui.cpp",
            "lib/imgui/generated/cimgui.cpp",
        );
        node.completeOne();
    }
}

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
        gfx.addLibraryPath(b.path("thirdparty/SDL/build/"));
        gfx.linkSystemLibrary("SDL3", .{ .needed = true });
        gfx.addLibraryPath(b.path("thirdparty/wgpu-native/target/debug/"));
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
        exe.root_module.addImport("core", core);
        exe.root_module.addImport("qoi", qoi);
        exe.root_module.addImport("wgm", wgm);
        exe.root_module.addImport("imgui", imgui);
        exe.root_module.addImport("gfx", gfx);
        // link_to_wgpu_and_sdl(b, exe);

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
            .test_runner = b.path("src/test_runner.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_tests.root_module.addImport("core", core);
        exe_tests.root_module.addImport("qoi", qoi);
        exe_tests.root_module.addImport("wgm", wgm);
        exe_tests.root_module.addImport("imgui", imgui);
        // link_to_wgpu_and_sdl(b, exe_tests);

        var run_exe_tests = b.addRunArtifact(exe_tests);
        run_exe_tests.has_side_effects = true;

        test_step.dependOn(&run_exe_tests.step);
    }

    // basic tests
    inline for (.{ "wgm", "qoi", "imgui" }) |lib_name| {
        const tests = b.addTest(.{
            .root_source_file = b.path(std.fmt.comptimePrint("lib/{s}/root.zig", .{lib_name})),
            .test_runner = b.path("src/test_runner.zig"),
            .target = target,
            .optimize = optimize,
        });

        var run_tests = b.addRunArtifact(tests);
        run_tests.has_side_effects = true;

        test_step.dependOn(&run_tests.step);
    }

    // inline for (library_names) |library_name| {
    // }
}
