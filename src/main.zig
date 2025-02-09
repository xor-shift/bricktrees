const std = @import("std");

const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const Ticker = @import("Ticker.zig");

const AnyThing = @import("AnyThing.zig");
const Globals = @import("globals.zig");

pub var g: Globals = undefined;

fn mkthing(comptime Thing: type, args: anytype, alloc: std.mem.Allocator) *Thing {
    const thing = alloc.create(Thing) catch @panic("");
    thing.* = @call(.auto, Thing.init, args) catch @panic("");
    return thing;
}

fn add_thing(thing: anytype) void {
    g.things.append(thing.to_any()) catch @panic("");
}

fn initialize_things(alloc: std.mem.Allocator) void {
    g = Globals.init(Globals.default_resolution, alloc) catch @panic("Globals.init");

    const camera = mkthing(@import("things/CameraThing.zig"), .{}, alloc);
    const map = mkthing(@import("things/MapThing.zig"), .{alloc}, alloc);
    const gui = mkthing(@import("things/GuiThing.zig"), .{}, alloc);
    const gpu = mkthing(@import("things/GpuThing.zig"), .{ map, alloc }, alloc);

    camera.gpu_thing = gpu;
    camera.map_thing = map;
    gpu.map_thing = map;

    g.gui = gui;

    add_thing(camera);
    add_thing(map);
    add_thing(gui);
    add_thing(gpu);

    map.reconfigure(.{
        .grid_dimensions = .{ 16, 16, 16 },
        .no_brickmaps = 128,
    }) catch @panic("map.reconfigure");

    g.resize(Globals.default_resolution) catch @panic("g.resize");
}

fn deinitialize_things() void {
    g.deinit();
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) std.log.warn("leaked memory", .{});

    initialize_things(alloc);
    defer deinitialize_things();

    var ticker: Ticker = .{ .config = .{
        .ns_per_tick = 50 * std.time.ns_per_ms,
        .mode = .aligned,
    } };

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

            g.new_tick(time - self.last);

            std.log.debug("tick took {d} ms", .{
                @as(f64, @floatFromInt(g.time() - time)) / std.time.ns_per_ms,
            });

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
    );
    defer ticker.stop();

    var frame_timer = try std.time.Timer.start();
    var ms_spent_last_frame: f64 = 1000.0;
    outer: while (true) {
        std.log.debug("new frame after {d} ms", .{ms_spent_last_frame});
        g.new_frame();

        const inter_frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        while (try sdl.poll_event()) |ev| {
            g.new_raw_event(ev) catch |e| {
                std.log.err("erorr while handling event: {any}", .{e});
            };

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                sdl.c.SDL_EVENT_KEY_DOWN => {
                    switch (ev.key.key) {
                        else => {},
                    }
                },
                else => {},
            }
        }

        const current_texture = g.surface.get_current_texture() catch |e| {
            if (e == wgpu.Error.Outdated) {
                std.log.debug("outdated", .{});
                continue;
            } else {
                return e;
            }
        };

        const current_texture_view = try current_texture.texture.create_view(.{
            .label = "current render texture view",
        });

        imgui.c.igNewFrame();
        defer imgui.c.igEndFrame();

        const command_encoder = try g.device.create_command_encoder(null);

        g.gui_step();

        g.render_step(command_encoder, current_texture_view);

        try g.gui.render(command_encoder, current_texture_view);

        current_texture_view.deinit();

        const command_buffer = try command_encoder.finish(null);
        command_encoder.deinit();

        g.queue.submit((&command_buffer)[0..1]);
        command_buffer.deinit();

        g.surface.present();

        current_texture.texture.deinit();

        const frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        ms_spent_last_frame = frame_time + inter_frame_time;
        // std.log.debug("{d}ms between frames, {d}ms during frame", .{ inter_frame_time, frame_time });
    }
}

test {
    // std.debug.assert(false);
    std.testing.refAllDecls(@import("brick/map.zig"));
    // std.testing.refAllDecls(@import("sgr.zig"));
}

// test "will leak" {
//     const alloc = std.testing.allocator_instance.allocator();
//     _ = try alloc.alloc(u8, 1);
// }
//
// test "will fail" {
//     try std.testing.expectEqual(true, false);
// }
