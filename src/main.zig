const std = @import("std");

const core = @import("core");
const dyn = @import("dyn");
const imgui = @import("imgui");
const qoi = @import("qoi");
const qov = @import("qov");
const tracy = @import("tracy");
const wgm = @import("wgm");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const Ticker = core.Ticker;

const Globals = @import("globals.zig");
const Things = @import("Things.zig");

const OBJFile = @import("core").OBJFile;

const PackedVoxel = qov.PackedVoxel;

const IThing = @import("IThing.zig");

pub const log_level: std.log.Level = .debug;

pub var g: Globals = undefined;

fn initialize_things(alloc: std.mem.Allocator) void {
    g = Globals.init(Globals.default_resolution, alloc) catch @panic("Globals.init");

    g.thing_store.add_thing(dyn.Fat(*IThing).init(&g), "globals", &.{});

    const GuiThing = @import("things/GuiThing.zig");
    _ = g.thing_store.add_new_thing(GuiThing, "gui", .{});

    const CameraThing = @import("things/CameraThing.zig");
    _ = g.thing_store.add_new_thing(CameraThing, "camera", .{});

    const VisualiserThing = @import("things/VisualiserThing.zig");
    _ = g.thing_store.add_new_thing(VisualiserThing, "visualiser", .{});

    const EditorThing = @import("things/EditorThing.zig");
    const sizes = .{
        .{ 1024, 1024, 1024 }, // hariball 1024
        .{ 1024, 246, 650 }, // conference
        .{ 2048, 496, 1300 }, // conference
        .{ 1860, 778, 1144 }, // sponza
    };
    _ = g.thing_store.add_new_thing(EditorThing, "editor", .{sizes[3]});

    // const DemoProvider = @import("voxel_providers/test.zig");
    // _ = g.thing_store.add_new_thing(DemoProvider, "test voxel provider", .{});

    // const ObjProvider = @import("voxel_providers/ObjLoader.zig");
    // _ = g.thing_store.add_new_thing(ObjProvider, "obj voxeliser", .{"scenes/hairball/hairball.obj", .{0} ** 3});

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "end", "gui" },
        .{ "start", "camera" },

        .{ "camera", "backend" },
        .{ "backend", "visualiser" },

        .{ "camera", "editor" },
        .{ "visualiser", "editor" },
        .{ "editor", "end" },
    }) |p| g.thing_store.render_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "start", "gui" },
        .{ "start", "camera" },

        .{ "start", "backend" },

        .{ "start", "visualiser" },
        .{ "start", "editor" },
    }) |p| g.thing_store.tick_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    for ([_]struct { []const u8, []const u8 }{
        .{ "globals", "start" },
        .{ "start", "gui" },
        .{ "start", "camera" },
        .{ "start", "backend" },
        .{ "start", "visualiser" },

        .{ "visualiser", "backend" },

        .{ "start", "editor" },
    }) |p| g.thing_store.event_graph.add_dependency(
        p.@"0",
        p.@"1",
    ) catch @panic("");

    g.do_resize(Globals.default_resolution) catch @panic("");
}

fn deinitialize_things() void {
    g.do_deinit();
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

    ticker = ticker;
    tick_fn = tick_fn;
    // try ticker.run(
    //     .{},
    //     TickFn.aufruf,
    //     .{&tick_fn},
    //     struct {
    //         pub fn aufruf() void {
    //             tracy.thread_name("tick thread");
    //         }
    //     }.aufruf,
    //     .{},
    // );
    // defer ticker.stop();

    var last_frame_start = g.time() - 16_500_000;
    outer: while (true) {
        while (try sdl.poll_event()) |ev| {
            g.submit_event(ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                else => {},
            }
        }

        const current_texture = g.surface.get_current_texture() catch |e| {
            if (e == wgpu.Error.Outdated) {
                std.log.debug("outdated", .{});
                try g.do_resize(g.window.get_size() catch unreachable);
                continue;
            } else {
                return e;
            }
        };

        tracy.frame_mark(null);

        const frame_start = g.time();
        const frametime_ns = frame_start - last_frame_start;
        defer last_frame_start = frame_start;

        const frametime_ms = @as(f64, @floatFromInt(frametime_ns)) / std.time.ns_per_ms;

        _ = frametime_ms;
        // std.log.debug("new frame after {d} ms", .{frametime_ms});
        g.new_frame();

        const current_texture_view = try current_texture.texture.create_view(.{
            .label = "current render texture view",
        });

        g.gui().new_frame(frametime_ns);

        const command_encoder = try g.device.create_command_encoder(null);

        {
            const _context_guard = imgui.ContextGuard.init(g.gui().c());
            defer _context_guard.deinit();

            g.thing_store.call_on_every_thing("do_gui", .{});
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
    std.testing.refAllDecls(@import("rt/ray.zig"));

    std.testing.refAllDecls(@import("DependencyGraph.zig"));

    std.testing.refAllDecls(@import("IVoxelProvider.zig"));
}
