const std = @import("std");

const core = @import("core");
const dyn = @import("dyn");
const imgui = @import("imgui");
const qoi = @import("qoi");
const wgm = @import("wgm");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const g = &@import("main.zig").g;

const DependencyGraph = @import("DependencyGraph.zig");

const Things = @import("Things.zig");

const IThing = @import("IThing.zig");
const IBackend = @import("backend/IBackend.zig");

const GuiThing = @import("things/GuiThing.zig");

const RotatingArena = core.RotatingArena;

pub const default_resolution: [2]usize = .{ 1280, 720 };

pub const DynStatic = dyn.ConcreteStuff(@This(), .{IThing});

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
    .bytes_per_pool = 32 * 1024 * 1024,
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

thing_store: Things,

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
            wgpu.FeatureName.ShaderI16,

            wgpu.FeatureName.BGRA8UnormStorage,
        },
        .required_limits = .{
            // .max_sampled_textures_per_shader_stage = 32768 + 64,
            // .max_storage_buffers_per_shader_stage = 32768 + 64,
            .max_buffer_size = 2 * 1024 * 1024 * 1024 - 1,
            .max_storage_buffer_binding_size = 2 * 1024 * 1024 * 1024 - 1,
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

    return .{
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

        .thing_store = Things.init(alloc) catch @panic("OOM"),
    };
}

/// Stub for IThing
pub fn deinit(_: *Self) void {}

pub fn do_deinit(self: *Self) void {
    defer self.* = undefined;

    self.thing_store.deinit();

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

// Stub for IThing
pub fn destroy(_: *Self, _: std.mem.Allocator) void {}

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

pub fn do_resize(self: *Self, dims: [2]usize) !void {
    self.thing_store.process_graph("event_graph", "resize", .{dims});
}

pub fn submit_event(self: *Self, ev: sdl.c.SDL_Event) void {
    self.thing_store.event(ev);
}

pub fn get_thing(self: *Self, thing_name: []const u8) ?dyn.Fat(*IThing) {
    return self.thing_store.things.get(thing_name);
}

pub fn gui(self: *Self) *GuiThing {
    return self.get_thing("gui").?.get_concrete(GuiThing);
}

pub fn backend(self: *Self) ?dyn.Fat(*IBackend) {
    const backend_thing = self.get_thing("backend") orelse return null;
    return backend_thing.sideways_cast(IBackend).?;
}

/// From IThing
/// DO NOT CALL DIRECTLY
pub fn resize(self: *Self, dims: [2]usize) !void {
    try self.surface.configure(.{
        .device = self.device,
        .format = .BGRA8Unorm,
        .usage = .{ .render_attachment = true },
        .view_formats = &.{.BGRA8UnormSrgb},
        .width = @intCast(dims[0]),
        .height = @intCast(dims[1]),
        // .present_mode = .Immediate,
        .present_mode = .Fifo,
    });
}

/// From IThing
/// DO NOT CALL DIRECTLY
pub fn do_gui(self: *Self) !void {
    imgui.c.igShowMetricsWindow(null);

    if (imgui.begin("backend", null, .{})) {
        _ = self;
        // if (self.backend) |backend| backend.options_ui(backend);
    }
    imgui.end();
}
