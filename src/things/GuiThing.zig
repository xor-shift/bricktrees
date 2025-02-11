const std = @import("std");

const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../AnyThing.zig");

const g = &@import("../main.zig").g;

const Self = @This();

context: imgui.WGPUContext,

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .deinit = Self.Any.deinit,
            .destroy = Self.Any.destroy,
            .on_resize = Self.Any.on_resize,
            .on_raw_event = Self.Any.on_raw_event,

            .render = Any.render,
        };
    }

    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn on_resize(self_arg: *anyopaque, dims: [2]usize) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_resize(dims);
    }

    pub fn on_raw_event(self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_raw_event(ev);
    }

    pub fn render(self_arg: *anyopaque, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(delta_ns, encoder, onto);
    }
};

pub fn init() !Self {
    const context = try imgui.WGPUContext.init(g.device, g.queue);
    errdefer context.deinit();

    return .{
        .context = context,
    };
}

pub fn deinit(self: *Self) void {
    defer self.* = undefined;

    self.context.deinit();
}

pub fn to_any(self: *Self) AnyThing {
    return Any.init(self);
}

pub fn c(self: *Self) *imgui.c.ImGuiContext {
    return self.context.context;
}

pub fn ctx_guard(self: *Self) imgui.ContextGuard {
    return imgui.ContextGuard.init(self.c());
}

pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    try self.context.render(encoder, onto);
}

pub fn on_resize(self: *Self, dims: [2]usize) !void {
    const _ctx_guard = self.ctx_guard();
    defer _ctx_guard.deinit();

    const io = imgui.c.igGetIO();
    io.*.DisplaySize = .{
        .x = @floatFromInt(dims[0]),
        .y = @floatFromInt(dims[1]),
    };
}

pub fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    imgui.sdl_event.translate_event(self.c(), ev);
}

pub fn new_frame(self: *Self, delta_ns: u64) void {
    const _guard = self.ctx_guard();
    defer _guard.deinit();

    imgui.c.igGetIO().*.DeltaTime = @floatCast(@as(f64, @floatFromInt(delta_ns)) / std.time.ns_per_s);
    imgui.c.igNewFrame();
}
