const std = @import("std");

const blas = @import("blas");
const sdl = @import("gfx").sdl;

pub const AnyThing = struct {
    thing: *anyopaque,

    deinit: *const fn (self_arg: *anyopaque) void,

    destroy: *const fn (self_arg: *anyopaque, on_alloc: std.mem.Allocator) void,

    /// Called after everything is registered and right before the frame loop starts.
    on_ready: *const fn (self_arg: *anyopaque) anyerror!void,

    /// Called right after the event loop exits and before anything like ImGui is deinitialized.
    on_shutdown: *const fn (self_arg: *anyopaque) anyerror!void,

    on_resize: *const fn (self_arg: *anyopaque, dims: blas.Vec2uz) anyerror!void,

    /// If, for example, a resize event is received, both this function and `on_resize` will be called.
    /// It is also possble for `on_resize` to be called but not `on_raw_event`
    on_raw_event: *const fn (self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void,
};
