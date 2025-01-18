const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const g = &@import("main.zig").g;

const AnyThing = @import("thing.zig").AnyThing;

const GuiThing = @import("things/gui.zig");

alloc: std.mem.Allocator,

instance: wgpu.Instance,

window: sdl.Window,
surface: wgpu.Surface,

adapter: wgpu.Adapter,
device: wgpu.Device,
queue: wgpu.Queue,

/// `AnyThing`s must be allocated on `alloc`.
things: std.ArrayList(AnyThing),

// unmanaged `Thing`s that get accessed often

gui: *GuiThing = undefined,

const max_n: usize = 2;
const arena_size: usize = 16 * 1024 * 1024;

const Any = struct {
    pub fn deinit(self_arg: *anyopaque) void {
        _ = self_arg;

        g.self_deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        _ = self_arg;
        _ = on_alloc;
    }

    pub fn on_ready(self_arg: *anyopaque) anyerror!void {
        _ = self_arg;
    }

    pub fn on_shutdown(self_arg: *anyopaque) anyerror!void {
        _ = self_arg;
    }

    pub fn on_resize(self_arg: *anyopaque, new: blas.Vec2uz) anyerror!void {
        _ = self_arg;
        try g.resize_impl(new);
    }

    pub fn on_raw_event(self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        _ = self_arg;
        try g.on_raw_event(ev);
    }
};

const Self = @This();

/// Initializes just the WebGPU stuff.
/// Assign to `g.gui` and then call `g.resize` after calling this.
pub fn init(dims: blas.Vec2uz, alloc: std.mem.Allocator) !Self {
    try sdl.init(.{ .video = true });
    errdefer sdl.deinit();

    imgui.init(alloc);
    errdefer imgui.deinit();

    const instance = wgpu.Instance.init();
    errdefer instance.deinit();
    std.log.debug("instance: {?p}", .{instance.handle});

    const window = try sdl.Window.init("test", dims);
    errdefer window.deinit();
    std.log.debug("window: {p}", .{window.handle});

    const surface = try window.get_surface(instance);
    errdefer surface.deinit();
    std.log.debug("surface: {?p}", .{surface.handle});

    const adapter = try instance.request_adapter_sync(.{
        .compatible_surface = surface,
        .backend_type = .Vulkan,
    });
    errdefer adapter.deinit();
    std.log.debug("surface: {?p}", .{surface.handle});

    const device = try adapter.request_device_sync(.{
        .label = "device",
        .required_features = &.{
            wgpu.FeatureName.BGRA8UnormStorage,
            wgpu.FeatureName.SampledTextureAndStorageBufferArrayNonUniformIndexing,
        },
    });
    errdefer device.deinit();
    std.log.debug("device: {?p}", .{device.handle});

    const queue = try device.get_queue();
    errdefer queue.deinit();
    std.log.debug("queue: {?p}", .{queue.handle});

    var ret: Self = .{
        .alloc = alloc,

        .instance = instance,

        .window = window,
        .surface = surface,

        .adapter = adapter,
        .device = device,
        .queue = queue,

        .things = std.ArrayList(AnyThing).init(alloc),
    };

    try ret.things.append(ret.to_any());

    return ret;
}

fn to_any(self: *Self) AnyThing {
    _ = self;

    return .{
        .thing = undefined,

        .deinit = Self.Any.deinit,
        .destroy = Self.Any.destroy,
        .on_ready = Self.Any.on_ready,
        .on_shutdown = Self.Any.on_shutdown,
        .on_resize = Self.Any.on_resize,
        .on_raw_event = Self.Any.on_raw_event,
    };
}

fn self_deinit(self: *Self) void {
    defer self.* = undefined;

    self.things.deinit();

    self.queue.deinit();
    self.device.deinit();
    self.adapter.deinit();

    self.surface.deinit();
    self.window.deinit();

    self.instance.deinit();

    imgui.deinit();
    sdl.deinit();
}

pub fn deinit(self: *Self) void {
    for (0..self.things.items.len) |i| {
        const j = self.things.items.len - i - 1;
        const thing = &self.things.items[j];

        thing.deinit(thing.thing);

        if (j == 0) { // lest we crash
            return;
        }

        thing.destroy(thing.thing, self.alloc);
        thing.* = undefined;
    }
}

fn resize_impl(self: *Self, dims: blas.Vec2uz) !void {
    try self.surface.configure(.{
        .device = self.device,
        .format = .BGRA8Unorm,
        .usage = .{ .render_attachment = true },
        .view_formats = &.{.BGRA8UnormSrgb},
        .width = @intCast(dims.x()),
        .height = @intCast(dims.y()),
        .present_mode = .Fifo,
    });
}

pub fn resize(self: *Self, dims: blas.Vec2uz) !void {
    for (self.things.items) |thing| {
        thing.on_resize(thing.thing, dims) catch |e| {
            std.log.err("error while calling on_resize on AnyThing @ {p} with dimensions {d}x{d}: {any}", .{
                thing.thing,
                dims.width(),
                dims.height(),
                e,
            });
        };
    }
}

pub fn new_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    for (self.things.items) |thing| {
        thing.on_raw_event(thing.thing, ev) catch |e| {
            std.log.err("error while calling on_raw_event on AnyThing @ {p}: {any}", .{
                thing.thing,
                e,
            });
        };
    }
}

fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    switch (ev.common.type) {
        sdl.c.SDL_EVENT_WINDOW_RESIZED => {
            const event = ev.window;
            const dims = blas.vec2uz(@intCast(event.data1), @intCast(event.data2));

            try self.resize(dims);
        },
        else => {
            // std.log.debug("unknown event", .{});
        },
    }
}

// The short name which stands for "n-frame-ly allocator" is for ease of typing.
// This returns an arena that will be valid until the end of the next n frames.
// An `n` valeu of 0 means that the arena will last 'til the end of the frame.
// Max n is determined beforehand and is most likely 2.
fn nfa(self: *Self, comptime n: usize) std.mem.Allocator {
    _ = self;
    _ = n;

    return undefined;
}
