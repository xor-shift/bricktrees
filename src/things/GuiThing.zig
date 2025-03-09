const std = @import("std");

const dyn = @import("dyn");
const imgui = @import("imgui");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const IThing = @import("../IThing.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{IThing});

context: imgui.WGPUContext,

pub fn init() !Self {
    const context = try imgui.WGPUContext.init(g.device, g.queue);
    errdefer context.deinit();

    return .{
        .context = context,
    };
}

pub fn deinit(self: *Self) void {
    self.context.deinit();
}

pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn c(self: *Self) *imgui.c.ImGuiContext {
    return self.context.context;
}

pub fn ctx_guard(self: *Self) imgui.ContextGuard {
    return imgui.ContextGuard.init(self.c());
}

pub fn raw_event(self: *Self, ev: sdl.c.SDL_Event) !bool {
    imgui.sdl_event.translate_event(self.c(), ev);
    const capture = imgui.c.igGetIO().*.WantCaptureKeyboard or imgui.c.igGetIO().*.WantCaptureMouse;
    return capture;
}

pub fn new_frame(self: *Self, delta_ns: u64) void {
    const _guard = self.ctx_guard();
    defer _guard.deinit();

    imgui.c.igGetIO().*.DeltaTime = @floatCast(@as(f64, @floatFromInt(delta_ns)) / std.time.ns_per_s);
    imgui.c.igNewFrame();
}

pub fn resize(self: *Self, dims: [2]usize) !void {
    const _ctx_guard = self.ctx_guard();
    defer _ctx_guard.deinit();

    const io = imgui.c.igGetIO();
    io.*.DisplaySize = .{
        .x = @floatFromInt(dims[0]),
        .y = @floatFromInt(dims[1]),
    };
}

pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    try self.context.render(encoder, onto);
}
