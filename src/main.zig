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
    g.queued_backend_selection = g.test_settings.backend;

    g.thing_store.add_thing(dyn.Fat(*IThing).init(&g), "globals", &.{});

    const GuiThing = @import("things/GuiThing.zig");
    _ = g.thing_store.add_new_thing(GuiThing, "gui", .{});

    const CameraThing = @import("things/CameraThing.zig");
    const camera_thing = g.thing_store.add_new_thing(CameraThing, "camera", .{});
    camera_thing.global_coords = g.test_settings.camera_pos;
    camera_thing.look = g.test_settings.camera_look;

    const VisualiserThing = @import("things/VisualiserThing.zig");
    _ = g.thing_store.add_new_thing(VisualiserThing, "visualiser", .{});

    const EditorThing = @import("things/EditorThing.zig");
    _ = g.thing_store.add_new_thing(EditorThing, "editor", .{.{ 64, 64, 64 }});

    const BVoxProvider = @import("voxel_providers/BVoxProvider.zig");
    _ = g.thing_store.add_new_thing(BVoxProvider, "bvox voxel provider", .{
        g.test_settings.filename,
        g.test_settings.file_dims,
    });

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

    //g.do_resize(Globals.default_resolution) catch @panic("");
    g.do_resize(g.test_settings.resolution) catch @panic("");
}

fn deinitialize_things() void {
    g.do_deinit();
}

/// There are better approaches than this. I needed this and I needed it fast
/// so here we are.
pub const MedianThing = struct {
    alloc: std.mem.Allocator,
    window: []f64,
    scratch: []f64,
    ptr: usize = 0,

    pub fn init(alloc: std.mem.Allocator, window_size: usize) !MedianThing {
        const window = try alloc.alloc(f64, window_size);
        errdefer alloc.free(window);

        const scratch = try alloc.alloc(f64, window_size);
        errdefer alloc.free(scratch);

        return .{
            .alloc = alloc,
            .window = window,
            .scratch = scratch,
        };
    }

    pub fn deinit(self: MedianThing) void {
        self.alloc.free(self.window);
    }

    pub fn median(self: MedianThing) f64 {
        @memcpy(self.scratch, self.window);
        std.mem.sort(f64, self.scratch, {}, std.sort.asc(f64));
        return self.scratch[self.scratch.len / 2];
    }

    pub fn average(self: MedianThing) f64 {
        var tally: f64 = 0;
        for (self.window) |v| tally += v;
        return tally / @as(f64, @floatFromInt(self.window.len));
    }

    pub fn add(self: *MedianThing, v: f64) void {
        self.window[self.ptr % self.window.len] = v;
        self.ptr += 1;
    }
};

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

    var last_ft_out: u64 = g.time();
    var ft_tracker = try MedianThing.init(alloc, 1024);
    var print_ct: usize = 0;

    var last_frame_start = g.time() - 16_500_000;
    outer: while (true) {
        while (try sdl.poll_event()) |ev| {
            g.submit_event(ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                else => {},
            }
        }

        try g.pre_frame();

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
        ft_tracker.add(frametime_ms);
        if ((g.time() - last_ft_out) >= std.time.ns_per_s) {
            last_ft_out = g.time();
            //std.log.debug("{d}ms", .{ft_tracker.median()});
        }
        if ((ft_tracker.ptr % ft_tracker.window.len) == 0) {
            defer print_ct += 1;
            std.fmt.format(std.io.getStdOut().writer(), "{d}ms\n", .{ft_tracker.average()}) catch {};
            // if (print_ct >= 2) {
            //     break;
            // }
        }

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

    std.testing.refAllDecls(@import("backend/svo/Backend.zig"));
}
