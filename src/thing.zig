const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

pub const AnyThing = struct {
    thing: *anyopaque,

    deinit: *const fn (self_arg: *anyopaque) void = struct {
        pub fn aufruf(_: *anyopaque) void {}
    }.aufruf,

    destroy: *const fn (self_arg: *anyopaque, on_alloc: std.mem.Allocator) void = struct {
        pub fn aufruf(_: *anyopaque, _: std.mem.Allocator) void {}
    }.aufruf,

    /// Called after everything is registered and right before the frame loop starts.
    on_ready: *const fn (self_arg: *anyopaque) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque) anyerror!void {}
    }.aufruf,

    /// Called right after the event loop exits and before anything like ImGui is deinitialized.
    on_shutdown: *const fn (self_arg: *anyopaque) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque) anyerror!void {}
    }.aufruf,

    on_resize: *const fn (self_arg: *anyopaque, dims: blas.Vec2uz) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque, _: blas.Vec2uz) anyerror!void {}
    }.aufruf,

    /// If, for example, a resize event is received, both this function and `on_resize` will be called.
    /// It is also possble for `on_resize` to be called but not `on_raw_event`
    on_raw_event: *const fn (self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque, _: sdl.c.SDL_Event) anyerror!void {}
    }.aufruf,

    do_gui: *const fn (self_arg: *anyopaque) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque) anyerror!void {}
    }.aufruf,

    render: *const fn (self: *anyopaque, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void = struct {
        pub fn aufruf(_: *anyopaque, _: wgpu.CommandEncoder, _: wgpu.TextureView) anyerror!void {}
    }.aufruf,
};
