const std = @import("std");

const core = @import("core");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const tracy = @import("tracy");
const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const Ticker = core.Ticker;

const AnyThing = @import("AnyThing.zig");
const Globals = @import("globals.zig");

const Things = @import("Things.zig");

pub var g: Globals = undefined;

fn initialize_things(alloc: std.mem.Allocator) void {
    g = Globals.init(Globals.default_resolution, alloc) catch @panic("Globals.init");

    g.thing_store.add_thing(&g.vtable_thing, "globals", &.{});

    const GuiThing = @import("things/GuiThing.zig");
    const gui = g.thing_store.add_new_thing(GuiThing, "gui", .{});

    const CameraThing = @import("things/CameraThing.zig");
    const camera = g.thing_store.add_new_thing(CameraThing, "camera", .{});

    const VisualiserThing = @import("things/VisualiserThing.zig");
    const visualiser = g.thing_store.add_new_thing(VisualiserThing, "visualiser", .{});

    const VoxelThing = @import("backend/brickmap/things/VoxelThing.zig");
    const voxel_thing = g.thing_store.add_new_thing(VoxelThing, "voxel manager", .{});

    const MapThing = @import("backend/brickmap/things/MapThing.zig");
    const map = g.thing_store.add_new_thing(MapThing, "map", .{});

    const GpuThing = @import("backend/brickmap/things/GpuThing.zig");
    const gpu = g.thing_store.add_new_thing(GpuThing, "gpu", .{map});

    const EditorThing = @import("things/EditorThing.zig");
    const editor = g.thing_store.add_new_thing(EditorThing, "editor", .{});

    g.thing_store.render_graph.add_dependency("globals", "start") catch @panic("");
    g.thing_store.render_graph.add_dependency("end", "gui") catch @panic("");
    g.thing_store.render_graph.add_dependency("start", "camera") catch @panic("");
    g.thing_store.render_graph.add_dependency("camera", "voxel manager") catch @panic("");
    g.thing_store.render_graph.add_dependency("voxel manager", "map") catch @panic("");
    g.thing_store.render_graph.add_dependency("map", "gpu") catch @panic("");
    g.thing_store.render_graph.add_dependency("gpu", "visualiser") catch @panic("");
    g.thing_store.render_graph.add_dependency("visualiser", "end") catch @panic("");
    g.thing_store.render_graph.add_dependency("visualiser", "end") catch @panic("");

    g.thing_store.render_graph.add_dependency("visualiser", "editor") catch @panic("");
    g.thing_store.render_graph.add_dependency("editor", "gui") catch @panic("");

    g.thing_store.tick_graph.add_dependency("globals", "start") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "gui") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "camera") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "visualiser") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "voxel manager") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "map") catch @panic("");
    g.thing_store.tick_graph.add_dependency("start", "gpu") catch @panic("");

    g.thing_store.event_graph.add_dependency("globals", "start") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "gui") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "camera") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "visualiser") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "voxel manager") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "map") catch @panic("");
    g.thing_store.event_graph.add_dependency("start", "gpu") catch @panic("");

    g.thing_store.event_graph.add_dependency("visualiser", "gpu") catch @panic("");
    g.thing_store.event_graph.add_dependency("map", "gpu") catch @panic("");

    g.thing_store.event_graph.add_dependency("start", "editor") catch @panic("");

    camera.map_thing = map;
    gpu.camera_thing = camera;
    gpu.map_thing = map;
    gpu.visualiser = visualiser;
    voxel_thing.map_thing = map;
    voxel_thing.camera_thing = camera;
    editor.camera = camera;

    // const QOIProvider = @import("voxel_providers/test2.zig");
    // const test_provider = g.alloc.create(QOIProvider) catch @panic("OOM");
    // test_provider.* = QOIProvider.from_file("sphere.qoi", 8) catch @panic("qoi");

    const DemoProvider = @import("voxel_providers/test.zig");
    const demo_provider = g.alloc.create(DemoProvider) catch @panic("OOM");
    demo_provider.* = .{};

    _ = voxel_thing.add_voxel_provider(&demo_provider.vtable_voxel_provider);
    _ = voxel_thing.add_voxel_provider(&editor.vtable_voxel_provider);

    g.gui = gui;

    map.reconfigure(.{
        // .grid_dimensions = .{ 209, 3, 209 },
        // .no_brickmaps = 65535 * 2 - 27,
        .grid_dimensions = .{ 19, 15, 19 },
        .no_brickmaps = 31 * 15 * 31,
    }) catch @panic("map.reconfigure");

    g.resize(Globals.default_resolution) catch @panic("g.resize");
}

fn deinitialize_things() void {
    g.deinit();
}

pub fn main() !void {
    tracy.thread_name("main");
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) std.log.warn("leaked memory", .{});

    initialize_things(alloc);
    defer deinitialize_things();

    var ticker: Ticker = .{
        .config = .{
            .ns_per_tick = 50 * std.time.ns_per_ms,
            .mode = .aligned,
        },
        .time_ctx = undefined,
        .time_provider = struct {
            pub fn aufruf(_: *anyopaque) u64 {
                return g.time();
            }
        }.aufruf,
    };

    const TickFn = struct {
        const Self = @This();

        rand: std.rand.Xoshiro256,
        last: u64 = 0,

        pub fn aufruf(self: *Self) void {
            const time = g.time();
            // std.log.debug("ticking at {d} (+ {d})", .{
            //     time,
            //     @as(f64, @floatFromInt(time - self.last)) / std.time.ns_per_ms,
            // });
            defer self.last = time;

            g.thing_store.tick(time - self.last);

            // std.log.debug("tick took {d} ms", .{
            //     @as(f64, @floatFromInt(g.time() - time)) / std.time.ns_per_ms,
            // });

            // const ms = self.rand.next() % 100;
            // std.time.sleep(ms * std.time.ns_per_ms);
        }
    };

    var tick_fn: TickFn = .{
        .rand = std.rand.Xoshiro256.init(
            @truncate(@as(u128, @intCast(std.time.nanoTimestamp()))),
        ),
    };

    try ticker.run(
        .{},
        TickFn.aufruf,
        .{&tick_fn},
        struct {
            pub fn aufruf() void {
                tracy.thread_name("tick thread");
            }
        }.aufruf,
        .{},
    );
    defer ticker.stop();

    var last_frame_start = g.time() - 16_500_000;
    outer: while (true) {
        tracy.frame_mark(null);

        const frame_start = g.time();
        const frametime_ns = frame_start - last_frame_start;
        defer last_frame_start = frame_start;

        const frametime_ms = @as(f64, @floatFromInt(frametime_ns)) / std.time.ns_per_ms;

        _ = frametime_ms;
        // std.log.debug("new frame after {d} ms", .{frametime_ms});
        g.new_frame();

        while (try sdl.poll_event()) |ev| {
            g.event(ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                else => {},
            }
        }

        const current_texture = g.surface.get_current_texture() catch |e| {
            if (e == wgpu.Error.Outdated) {
                std.log.debug("outdated", .{});
                try g.resize(g.window.get_size() catch unreachable);
                continue;
            } else {
                return e;
            }
        };

        const current_texture_view = try current_texture.texture.create_view(.{
            .label = "current render texture view",
        });

        g.gui.new_frame(frametime_ns);

        const command_encoder = try g.device.create_command_encoder(null);

        {
            const _context_guard = imgui.ContextGuard.init(g.gui.c());
            defer _context_guard.deinit();

            g.thing_store.call_on_every_thing("gui", .{});
        }

        g.thing_store.render(frametime_ns, command_encoder, current_texture_view);

        current_texture_view.deinit();

        const command_buffer = try command_encoder.finish(null);
        command_encoder.deinit();

        g.queue.submit((&command_buffer)[0..1]);
        command_buffer.deinit();

        g.surface.present() catch {};

        current_texture.texture.deinit();
    }
}

test {
    // std.debug.assert(false);

    std.testing.refAllDecls(@import("backend/brickmap/Backend.zig"));
    std.testing.refAllDecls(@import("worker_pool.zig"));
    std.testing.refAllDecls(@import("rt/ray.zig"));

    std.testing.refAllDecls(@import("DependencyGraph.zig"));
}

// test "will leak" {
//     const alloc = std.testing.allocator_instance.allocator();
//     _ = try alloc.alloc(u8, 1);
// }
//
// test "will fail" {
//     try std.testing.expectEqual(true, false);
// }
