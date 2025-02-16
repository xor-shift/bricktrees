const std = @import("std");

const core = @import("core");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const g = &@import("main.zig").g;

const DependencyGraph = @import("DependencyGraph.zig");

const Things = @import("Things.zig");

const AnyThing = @import("AnyThing.zig");
const GuiThing = @import("things/GuiThing.zig");

const RotatingArena = core.RotatingArena;

pub const default_resolution: [2]usize = .{ 1280, 720 };

clock_mutex: std.Thread.Mutex,
clock: std.time.Timer,

alloc: std.mem.Allocator,

instance: wgpu.Instance,

window: sdl.Window,
surface: wgpu.Surface,

adapter: wgpu.Adapter,
device: wgpu.Device,
queue: wgpu.Queue,

frame_no: usize = 0,

frame_ra: RotatingArena(.{
    .no_pools = 1,
    .bytes_per_pool = 16 * 1024 * 1024,
}),
frame_alloc: std.mem.Allocator = undefined,

biframe_ra: RotatingArena(.{
    .no_pools = 2,
    .bytes_per_pool = 128 * 1024 * 1024,
}),
biframe_alloc: std.mem.Allocator,

tick_ra: RotatingArena(.{
    .no_pools = 1,
    .bytes_per_pool = 16 * 1024 * 1024,
}),
tick_alloc: std.mem.Allocator = undefined,

/// `AnyThing`s must be allocated on `alloc`.
things: std.ArrayList(AnyThing),

thing_store: Things,

// Normally, you should store pointers to other `Thing`s you want inside your
// own `Thing` but this is the one exception as every`Thing` needs it.
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
        };
    }

    pub fn on_ready(_: *anyopaque) anyerror!void {}

    pub fn on_shutdown(_: *anyopaque) anyerror!void {}

    pub fn on_resize(_: *anyopaque, new: [2]usize) anyerror!void {
        try g.resize_impl(new);
    }

    pub fn on_raw_event(_: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try g.on_raw_event(ev);
    }

    pub fn do_gui(_: *anyopaque) anyerror!void {
        try g.do_gui();
    }
};

const Self = @This();

/// Initializes just the WebGPU stuff.
/// Assign to `g.gui` and then call `g.resize` after calling this.
pub fn init(dims: [2]usize, alloc: std.mem.Allocator) !Self {
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
                // .max_sampled_textures_per_shader_stage = 32768 + 64,
                // .max_storage_buffers_per_shader_stage = 32768 + 64,
                .max_buffer_size = 1 * 1024 * 1024 * 1024,
            },
        },
    });
    errdefer device.deinit();
    std.log.debug("device: {?p}", .{device.handle});

    const queue = try device.get_queue();
    errdefer queue.deinit();
    std.log.debug("queue: {?p}", .{queue.handle});

    var frame_ra = try @TypeOf(@as(Self, undefined).frame_ra).init();
    errdefer frame_ra.deinit();

    var biframe_ra = try @TypeOf(@as(Self, undefined).biframe_ra).init();
    errdefer biframe_ra.deinit();
    // this needs to be ready on init
    const biframe_alloc = biframe_ra.rotate();

    var tick_ra = try @TypeOf(@as(Self, undefined).tick_ra).init();
    errdefer tick_ra.deinit();

    var ret: Self = .{
        .clock_mutex = .{},
        .clock = try std.time.Timer.start(),

        .alloc = alloc,

        .instance = instance,

        .window = window,
        .surface = surface,

        .adapter = adapter,
        .device = device,
        .queue = queue,

        .frame_ra = frame_ra,
        .biframe_ra = biframe_ra,
        .biframe_alloc = biframe_alloc,
        .tick_ra = tick_ra,

        .things = std.ArrayList(AnyThing).init(alloc),

        .thing_store = Things.init(alloc) catch @panic("OOM"),
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

    self.frame_ra.deinit();
    self.biframe_ra.deinit();
    self.tick_ra.deinit();
}

/// Returns the number of nanoseconds that passed since the start of the program.
pub fn time(self: *Self) u64 {
    self.clock_mutex.lock();
    defer self.clock_mutex.unlock();

    return self.clock.read();
}

pub fn new_frame(self: *Self) void {
    defer self.frame_no += 1;

    self.frame_alloc = self.frame_ra.rotate();
    self.biframe_alloc = self.biframe_ra.rotate();
}

pub fn new_tick(self: *Self, delta_ns: u64) void {
    self.tick_alloc = self.tick_ra.rotate();

    self.call_on_every_thing("on_tick", .{delta_ns});
}

fn resize_impl(self: *Self, dims: [2]usize) !void {
    try self.surface.configure(.{
        .device = self.device,
        .format = .BGRA8Unorm,
        .usage = .{ .render_attachment = true },
        .view_formats = &.{.BGRA8UnormSrgb},
        .width = @intCast(dims[0]),
        .height = @intCast(dims[1]),
        .present_mode = .Mailbox,
        // .present_mode = .Fifo,
    });
}

fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    switch (ev.common.type) {
        sdl.c.SDL_EVENT_WINDOW_RESIZED => {
            const event = ev.window;
            const dims: [2]usize = .{ @intCast(event.data1), @intCast(event.data2) };

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

fn call_on_every_thing(self: *Self, comptime fun_str: []const u8, args: anytype) void {
    for (self.things.items) |thing| {
        const fun = @field(thing, fun_str);
        @call(.auto, fun, .{thing.thing} ++ args) catch |e| {
            std.log.err("error calling " ++ fun_str ++ " on AnyThing @ {p}: {any}", .{
                thing.thing,
                e,
            });
        };
    }
}

pub fn resize(self: *Self, dims: [2]usize) !void {
    self.call_on_every_thing("on_resize", .{dims});
}

pub fn new_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    self.call_on_every_thing("on_raw_event", .{ev});
}

pub fn gui_step(self: *Self) void {
    const _context_guard = imgui.ContextGuard.init(self.gui.c());
    defer _context_guard.deinit();

    self.call_on_every_thing("do_gui", .{});
}

pub fn render_step(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) void {
    self.call_on_every_thing("render", .{ delta_ns, encoder, onto });
}
