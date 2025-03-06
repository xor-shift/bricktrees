const std = @import("std");

const dyn = @import("dyn");
const imgui = @import("imgui");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const util = @import("vtable_utils.zig");

const Self = @This();

pub const DynStatic = dyn.IFaceStuff(Self);

pub fn deinit(_: dyn.Fat(*Self)) void {}

pub fn destroy(_: dyn.Fat(*Self), on_alloc: std.mem.Allocator) void {
    _ = on_alloc;
}

/// Called after everything is registered and right before the frame loop starts.
pub fn ready(_: dyn.Fat(*Self)) anyerror!void {}

/// Called right after the event loop exits and before anything like ImGui is deinitialized.
pub fn shutdown(_: dyn.Fat(*Self)) anyerror!void {}

pub fn resize(_: dyn.Fat(*Self), dims: [2]usize) anyerror!void {
    _ = dims;
}

/// If, for example, a resize event is received, both this function and `on_resize` will be called.
/// It is also possble for `on_resize` to be called but not `on_raw_event`
pub fn raw_event(_: dyn.Fat(*Self), ev: sdl.c.SDL_Event) anyerror!void {
    _ = ev;
}

pub fn process_tick(_: dyn.Fat(*Self), delta_ns: u64) anyerror!void {
    _ = delta_ns;
}

pub fn do_gui(_: dyn.Fat(*Self)) anyerror!void {}

pub fn render(_: dyn.Fat(*Self), delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
    _ = delta_ns;
    _ = encoder;
    _ = onto;
}

