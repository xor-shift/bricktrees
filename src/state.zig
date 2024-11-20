const std = @import("std");

const sdl = @import("sdl.zig");
const wgpu = @import("wgpu/wgpu.zig");

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

resize_notify: std.ArrayListUnmanaged(ResizeNotify) = .{},

pub fn init(alloc: std.mem.Allocator) !State {
    const instance = wgpu.Instance.init();

    try sdl.init(.{
        .video = true,
    });

    const window = try sdl.Window.init("Test", 640, 360);
    const surface = try window.get_surface(instance);
    std.log.debug("surface: {?p}", .{surface.handle});

    const adapter = try instance.request_adapter_sync(.{
        .compatible_surface = surface,
        .backend_type = .Vulkan,
    });
    std.log.debug("adapter: {?p}", .{adapter.handle});

    const device = try adapter.request_device_sync(.{
        .label = "device",
        .required_features = &.{
            wgpu.FeatureName.BGRA8UnormStorage,
        },
    });
    std.log.debug("device: {?p}", .{device.handle});

    const queue = try device.get_queue();
    std.log.debug("queue: {?p}", .{queue.handle});

    var ret: State = .{
        .alloc = alloc,

        .instance = instance,

        .window = window,
        .surface = surface,

        .adapter = adapter,
        .device = device,
        .queue = queue,
    };

    try ret.resize(640, 360);

    return ret;
}

pub fn deinit(self: State) void {
    _ = self;
    sdl.deinit();
}

pub fn resize(self: *State, width: usize, height: usize) !void {
    try self.surface.configure(.{
        .device = self.device,
        .format = .BGRA8Unorm,
        .usage = .{ .render_attachment = true },
        .view_formats = &.{.BGRA8UnormSrgb},
        .width = @intCast(width),
        .height = @intCast(height),
    });

    try self.window.resize(width, height);
}
