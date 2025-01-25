const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("thing.zig").AnyThing;
const Globals = @import("globals.zig");

const GPUThing = @import("things/gpu.zig");
const GuiThing = @import("things/gui.zig");

pub var g: Globals = undefined;

fn initialize_things(alloc: std.mem.Allocator) void {
    g = Globals.init(Globals.default_resolution, alloc) catch @panic("Globals.init");

    const gui = alloc.create(GuiThing) catch @panic("alloc.create(GuiThing)");
    gui.* = GuiThing.init() catch @panic("GuiThing.init()");
    g.things.append(gui.to_any()) catch @panic("g.things.append");

    g.gui = gui;

    const gpu = alloc.create(GPUThing) catch @panic("alloc.create(GPUThing)");
    gpu.* = GPUThing.init(alloc) catch @panic("GPUThing.init()");
    g.things.append(gpu.to_any()) catch @panic("g.things.append");

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

    var frame_timer = try std.time.Timer.start();
    var ms_spent_last_frame: f64 = 1000.0;
    outer: while (true) {
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
    std.testing.refAllDecls(@import("sgr.zig"));
}

// test "will leak" {
//     const alloc = std.testing.allocator_instance.allocator();
//     _ = try alloc.alloc(u8, 1);
// }
//
// test "will fail" {
//     try std.testing.expectEqual(true, false);
// }
