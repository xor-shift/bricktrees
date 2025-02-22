const std = @import("std");

const PackedVoxel = @import("voxel.zig").PackedVoxel;

pub fn always_draw(_: *anyopaque, _: [2][3]isize) bool {
    return true;
}

pub fn never_draw(_: *anyopaque, _: [2][3]isize) bool {
    return false;
}

provider: *anyopaque,

/// Guaranteed to be called from the render thread.
///
/// This is so that the voxel provider locks any locks that need to be locked
/// before `should_redraw` and `draw` are called.
render_start: *const fn (self_arg: *anyopaque) void = struct {
    pub fn aufruf(_: *anyopaque) void {}
}.aufruf,

render_end: *const fn (self_arg: *anyopaque) void = struct {
    pub fn aufruf(_: *anyopaque) void {}
}.aufruf,

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is _currently_ occupied by the object or objects this provider represents
should_draw: *const fn (self_arg: *anyopaque, range: [2][3]isize) bool,

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is currently occupied _AND_ used not to be occupied during the previous render
/// - The given range is not occupied _AND_ used to be occupied during the previous render
/// - The given range was occupied, is occupied, and the contents of it changed since the previous render
should_redraw: *const fn (self_arg: *anyopaque, range: [2][3]isize) bool,

/// Might be called concurrently
draw: *const fn (self_arg: *anyopaque, range: [2][3]isize, storage: []PackedVoxel) void,
