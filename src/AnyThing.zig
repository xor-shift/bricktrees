const std = @import("std");

const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const util = @import("vtable_utils.zig");

const AnyThing = @This();

deinit: *const fn (self: *AnyThing) void,

destroy: *const fn (self: *AnyThing, on_alloc: std.mem.Allocator) void,

/// Called after everything is registered and right before the frame loop starts.
ready: *const fn (self: *AnyThing) anyerror!void,

/// Called right after the event loop exits and before anything like ImGui is deinitialized.
shutdown: *const fn (self: *AnyThing) anyerror!void,

resize: *const fn (self: *AnyThing, dims: [2]usize) anyerror!void,

/// If, for example, a resize event is received, both this function and `on_resize` will be called.
/// It is also possble for `on_resize` to be called but not `on_raw_event`
raw_event: *const fn (self: *AnyThing, ev: sdl.c.SDL_Event) anyerror!void,

tick: *const fn (self: *AnyThing, delta_ns: u64) anyerror!void,

gui: *const fn (self: *AnyThing) anyerror!void,

render: *const fn (self: *AnyThing, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void,

pub fn mk_vtable(comptime Thing: type) AnyThing {
    return @import("vtable_utils.zig").mk_vtable(Thing, AnyThing, "thing", struct {
        pub fn deinit(_: *AnyThing) void {}
        pub fn destroy(_: *AnyThing, _: std.mem.Allocator) void {}
        pub fn ready(_: *AnyThing) anyerror!void {}
        pub fn shutdown(_: *AnyThing) anyerror!void {}
        pub fn resize(_: *AnyThing, _: [2]usize) anyerror!void {}
        pub fn raw_event(_: *AnyThing, _: sdl.c.SDL_Event) anyerror!void {}
        pub fn tick(_: *AnyThing, _: u64) anyerror!void {}
        pub fn gui(_: *AnyThing) anyerror!void {}
        pub fn render(_: *AnyThing, _: u64, _: wgpu.CommandEncoder, _: wgpu.TextureView) anyerror!void {}
    });
}
