const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const g = &@import("main.zig").g;

const AnyThing = @import("thing.zig").AnyThing;

const GuiThing = @import("things/gui.zig");

pub const default_resolution: blas.Vec2uz = blas.vec2uz(1280, 720);

const nfa_max_n: usize = 2;
const nfa_arena_size: usize = 16 * 1024 * 1024;

const NFABufferType = [nfa_arena_size]u8;
// one extra arena for safety
const NFABuffersType = [(nfa_max_n + 2) * (nfa_max_n + 1) / 2]NFABufferType;

alloc: std.mem.Allocator,

instance: wgpu.Instance,

window: sdl.Window,
surface: wgpu.Surface,

adapter: wgpu.Adapter,
device: wgpu.Device,
queue: wgpu.Queue,

frame_no: usize = 0,
nfa_buffers: *NFABuffersType,
nf_allocators: [nfa_max_n][2]std.heap.FixedBufferAllocator = undefined,
nf_arenas: [nfa_max_n]std.heap.ArenaAllocator = undefined,

/// `AnyThing`s must be allocated on `alloc`.
things: std.ArrayList(AnyThing),

// unmanaged `Thing`s that get accessed often

gui: *GuiThing = undefined,

const Any = struct {
    fn init(self: *Self) AnyThing {
        _ = self;

        return .{
            .thing = undefined,

            .on_ready = Self.Any.on_ready,
            .on_shutdown = Self.Any.on_shutdown,
            .on_resize = Self.Any.on_resize,
            .on_raw_event = Self.Any.on_raw_event,

            .do_gui = Self.Any.do_gui,
            .render = Self.Any.render,
        };
    }

    pub fn on_ready(_: *anyopaque) anyerror!void {}

    pub fn on_shutdown(_: *anyopaque) anyerror!void {}

    pub fn on_resize(_: *anyopaque, new: blas.Vec2uz) anyerror!void {
        try g.resize_impl(new);
    }

    pub fn on_raw_event(_: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try g.on_raw_event(ev);
    }

    pub fn do_gui(_: *anyopaque) anyerror!void {
        try g.do_gui();
    }

    pub fn render(_: *anyopaque, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        _ = encoder;
        _ = onto;
        // try g.render(encoder, onto);
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
            wgpu.FeatureName.BufferBindingArray,
            wgpu.FeatureName.TextureBindingArray,

            wgpu.FeatureName.StorageResourceBindingArray,

            wgpu.FeatureName.SampledTextureAndStorageBufferArrayNonUniformIndexing,

            wgpu.FeatureName.BGRA8UnormStorage,
        },
        .required_limits = .{
            .limits = .{
                .max_sampled_textures_per_shader_stage = 2048,
                .max_storage_buffers_per_shader_stage = 2048,
            },
        },
    });
    errdefer device.deinit();
    std.log.debug("device: {?p}", .{device.handle});

    const queue = try device.get_queue();
    errdefer queue.deinit();
    std.log.debug("queue: {?p}", .{queue.handle});

    const nfa_buffers = try alloc.create(NFABuffersType);
    errdefer alloc.destroy(nfa_buffers);

    var ret: Self = .{
        .alloc = alloc,

        .instance = instance,

        .window = window,
        .surface = surface,

        .adapter = adapter,
        .device = device,
        .queue = queue,

        .nfa_buffers = nfa_buffers,

        .things = std.ArrayList(AnyThing).init(alloc),
    };

    try ret.things.append(ret.to_any());

    return ret;
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn deinit(self: *Self) void {
    for (0..self.things.items.len) |i| {
        const j = self.things.items.len - i - 1;

        if (j == 0) {
            break;
        }

        const thing = &self.things.items[j];

        thing.deinit(thing.thing);

        thing.destroy(thing.thing, self.alloc);
        thing.* = undefined;
    }

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

    self.alloc.destroy(self.nfa_buffers);
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

pub fn gui_step(self: *Self) void {
    const _context_guard = imgui.ContextGuard.init(self.gui.c());
    defer _context_guard.deinit();

    for (self.things.items) |thing| {
        thing.do_gui(thing.thing) catch |e| {
            std.log.err("error while calling do_gui on AnyThing @ {p}: {any}", .{
                thing.thing,
                e,
            });
        };
    }
}

pub fn render_step(self: *Self, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) void {
    for (self.things.items) |thing| {
        thing.render(thing.thing, encoder, onto) catch |e| {
            std.log.err("error while calling render on AnyThing @ {p}: {any}", .{
                thing.thing,
                e,
            });
        };
    }
}

pub fn fa_new_frame(self: *Self) void {
    defer self.frame_no += 1;

    for (0..nfa_max_n) |i| {
        const sz_before = (i + 2) * (i + 1) / 2 - 1;
        const sz_current = i + 2;

        const current = self.nfa_buffers.*[sz_before .. sz_before + sz_current];

        const new = &current[self.frame_no % (i + 2)];
        const old = &current[(self.frame_no + i + 1) % (i + 2)];

        @memset(new.*[0..], undefined);
        @memset(old.*[0..], undefined);

        self.nf_allocators[i][(self.frame_no + 1) % 2] = undefined;
        self.nf_allocators[i][self.frame_no % 2] = std.heap.FixedBufferAllocator.init(new);
        self.nf_arenas[i] = std.heap.ArenaAllocator.init(self.nf_allocators[i][self.frame_no % 2].threadSafeAllocator());
    }
}

// The short name which stands for "n-frame-ly allocator" is for ease of typing.
//
// This returns an arena that will be valid until the end of the next n
// frame(s).
//
// An `n` value of 1 means that the arena will last until the end of the frame.
//
// The max. value of n is determined at compile time and is most likely to be 2.
pub fn nfa(self: *Self, comptime n: usize) std.mem.Allocator {
    if (n > nfa_max_n) @compileError("n may not exceed nfa_max_n");

    return self.nf_arenas[n - 1].allocator();
}

pub fn nfa_alloc(self: *Self, comptime n: usize, comptime T: type, sz: usize) []T {
    return self.nfa(n).alloc(T, sz) catch @panic("NFA OOM");
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

fn do_gui(self: *Self) !void {
    _ = self;

    imgui.c.igShowMetricsWindow(null);
}
