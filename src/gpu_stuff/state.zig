const std = @import("std");

const blas = @import("../blas/blas.zig");
const sdl = @import("../sdl.zig");
const wgpu = @import("../wgpu/wgpu.zig");

const State = @This();

pub const ResizeNotify = struct {
    callback: *const fn (ctx: *anyopaque, width: usize, height: usize) anyerror!void,
    context: *anyopaque,
};

alloc: std.mem.Allocator,

instance: wgpu.Instance,

window: sdl.Window,
surface: wgpu.Surface,

adapter: wgpu.Adapter,
device: wgpu.Device,
queue: wgpu.Queue,

pub fn init(alloc: std.mem.Allocator) !State {
    const instance = wgpu.Instance.init();

    try sdl.init(.{
        .video = true,
    });

    const window = try sdl.Window.init("Test", 1280, 720);
    const surface = try window.get_surface(instance);

    const adapter = try instance.request_adapter_sync(.{
        .compatible_surface = surface,
        .backend_type = .Vulkan,
    });

    const device = try adapter.request_device_sync(.{
        .label = "device",
        .required_features = &.{
            wgpu.FeatureName.BGRA8UnormStorage,
        },
    });

    const queue = try device.get_queue();

    var ret: State = .{
        .alloc = alloc,

        .instance = instance,

        .window = window,
        .surface = surface,

        .adapter = adapter,
        .device = device,
        .queue = queue,
    };

    try ret.resize(blas.vec2uz(640, 360));

    return ret;
}

pub fn deinit(self: State) void {
    _ = self;
    sdl.deinit();
}

pub fn resize(self: *State, dims: blas.Vec2uz) !void {
    try self.surface.configure(.{
        .device = self.device,
        .format = .BGRA8Unorm,
        .usage = .{ .render_attachment = true },
        .view_formats = &.{.BGRA8UnormSrgb},
        .width = @intCast(dims.width()),
        .height = @intCast(dims.height()),
        .present_mode = .Fifo,
    });

    try self.window.resize(dims);
}
