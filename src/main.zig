const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const qoi = @import("qoi");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const Gui = @import("imgui").WGPUContext;

pub const Globals = struct {
    instance: wgpu.Instance,

    window: sdl.Window,
    surface: wgpu.Surface,

    adapter: wgpu.Adapter,
    device: wgpu.Device,
    queue: wgpu.Queue,

    // unmanaged
    gui: Gui = undefined,

    const max_n: usize = 2;
    const arena_size: usize = 16 * 1024 * 1024;

    /// Initializes just the WebGPU stuff.
    /// Assign to `g.gui` and then call `g.resize` after calling this.
    fn init(dims: blas.Vec2uz) !Globals {
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

        return .{
            .instance = instance,
            .window = window,
            .surface = surface,
            .adapter = adapter,
            .device = device,
            .queue = queue,
        };
    }

    fn deinit(self: *Globals) void {
        defer self.* = undefined;

        self.queue.deinit();
        self.device.deinit();
        self.adapter.deinit();

        self.surface.deinit();
        self.window.deinit();

        self.instance.deinit();
    }

    fn resize(self: *Globals, dims: blas.Vec2uz) !void {
        try self.surface.configure(.{
            .device = self.device,
            .format = .BGRA8Unorm,
            .usage = .{ .render_attachment = true },
            .view_formats = &.{.BGRA8UnormSrgb},
            .width = @intCast(dims.x()),
            .height = @intCast(dims.y()),
            .present_mode = .Fifo,
        });

        const io = imgui.c.igGetIO();
        io.*.DisplaySize = .{
            .x = @floatFromInt(dims.x()),
            .y = @floatFromInt(dims.y()),
        };
    }

    // The short name which stands for "n-frame-ly allocator" is for ease of typing.
    // This returns an arena that will be valid until the end of the next n frames.
    // An `n` valeu of 0 means that the arena will last 'til the end of the frame.
    // Max n is determined beforehand and is most likely 2.
    fn nfa(self: *Globals, comptime n: usize) std.mem.Allocator {
        _ = self;
        _ = n;

        return undefined;
    }
};

pub var g: Globals = undefined;

fn initialize_things(alloc: std.mem.Allocator) !void {
    try sdl.init(.{ .video = true });
    errdefer sdl.deinit();

    g = try Globals.init(blas.vec2uz(1280, 720));
    errdefer {
        g.deinit();
        g = undefined;
    }

    imgui.init(alloc);
    errdefer imgui.deinit();

    g.gui = try Gui.init(g.device, g.queue, alloc);
    errdefer g.gui.deinit();

    try g.resize(blas.vec2uz(1280, 720));
}

fn deinitialize_things() void {
    g.gui.deinit();
    imgui.deinit();
    g.deinit();
    sdl.deinit();
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) std.log.warn("leaked memory", .{});

    initialize_things(alloc) catch |e| {
        std.log.err("initialization failed: {any}", .{e});
        std.process.exit(1);
    };

    defer deinitialize_things();

    var frame_timer = try std.time.Timer.start();
    var ms_spent_last_frame: f64 = 1000.0;
    outer: while (true) {
        const inter_frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        while (try sdl.poll_event()) |ev| {
            imgui.sdl_event.translate_event(g.gui.context, ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                sdl.c.SDL_EVENT_WINDOW_RESIZED => {
                    const event = ev.window;
                    const dims = blas.vec2uz(@intCast(event.data1), @intCast(event.data2));

                    _ = dims;
                },
                sdl.c.SDL_EVENT_KEY_DOWN => {
                    switch (ev.key.key) {
                        else => {},
                    }
                },
                sdl.c.SDL_EVENT_MOUSE_MOTION => {},
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {},
                else => {
                    // std.log.debug("unknown event", .{});
                },
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

        imgui.c.igShowDemoWindow(null);
        imgui.c.igShowMetricsWindow(null);
        imgui.c.igShowDebugLogWindow(null);

        const command_encoder = try g.device.create_command_encoder(null);

        try g.gui.render(command_encoder, current_texture_view);

        current_texture_view.release();

        const command_buffer = try command_encoder.finish(null);
        command_encoder.release();

        g.queue.submit((&command_buffer)[0..1]);
        command_buffer.release();

        g.surface.present();

        current_texture.texture.deinit();

        const frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        ms_spent_last_frame = frame_time + inter_frame_time;
        // std.log.debug("{d}ms between frames, {d}ms during frame", .{ inter_frame_time, frame_time });
    }
}

test {
    // std.debug.assert(false);
}
