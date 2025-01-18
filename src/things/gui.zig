const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../thing.zig").AnyThing;

const g = &@import("../main.zig").g;

const Self = @This();

context: imgui.WGPUContext,

pub const Any = struct {
    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn on_ready(self_arg: *anyopaque) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_ready();
    }

    pub fn on_shutdown(self_arg: *anyopaque) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_shutdown();
    }

    pub fn on_resize(self_arg: *anyopaque, dims: blas.Vec2uz) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_resize(dims);
    }

    pub fn on_raw_event(self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_raw_event(ev);
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

pub fn c(self: *Self) *imgui.c.ImGuiContext {
    return self.context.context;
}

pub fn ctx_guard(self: *Self) imgui.ContextGuard {
    return imgui.ContextGuard.init(self.c());
}

pub fn render(self: *Self, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    try self.context.render(encoder, onto);
}

pub fn to_any(self: *Self) AnyThing {
    return .{
        .thing = @ptrCast(self),

        .deinit = Self.Any.deinit,
        .destroy = Self.Any.destroy,
        .on_ready = Self.Any.on_ready,
        .on_shutdown = Self.Any.on_shutdown,
        .on_resize = Self.Any.on_resize,
        .on_raw_event = Self.Any.on_raw_event,
    };
}

pub fn on_ready(self: *Self) !void {
    _ = self;
}

pub fn on_shutdown(self: *Self) !void {
    _ = self;
}

pub fn on_resize(self: *Self, dims: blas.Vec2uz) !void {
    const _ctx_guard = self.ctx_guard();
    defer _ctx_guard.deinit();

    const io = imgui.c.igGetIO();
    io.*.DisplaySize = .{
        .x = @floatFromInt(dims.x()),
        .y = @floatFromInt(dims.y()),
    };
}

pub fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    imgui.sdl_event.translate_event(self.c(), ev);
}
