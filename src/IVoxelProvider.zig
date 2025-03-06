const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const PackedVoxel = @import("voxel.zig").PackedVoxel;

const Self = @This();

pub const DynStatic = dyn.IFaceStuff(Self);

/// Guaranteed to be called from the render thread.
///
/// This is so that the voxel provider locks any locks that need to be locked
/// before `should_redraw` and `draw` are called.
pub fn voxel_draw_start(_: dyn.Fat(*Self)) void {}

pub fn voxel_draw_end(_: dyn.Fat(*Self)) void {}

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is _currently_ occupied by the object or objects this provider represents
pub fn should_draw_voxels(_: dyn.Fat(*Self), range: [2][3]isize) bool {
    _ = range;
    return true;
}

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is currently occupied _AND_ used not to be occupied during the previous render
/// - The given range is not occupied _AND_ used to be occupied during the previous render
/// - The given range was occupied, is occupied, and the contents of it changed since the previous render
pub fn should_redraw_voxels(_: dyn.Fat(*Self), range: [2][3]isize) bool {
    _ = range;
    return false;
}

/// Might be called concurrently
pub const draw_voxels = fn (_: dyn.Fat(*Self), range: [2][3]isize, storage: []PackedVoxel) void;

pub fn overlap_info(draw_range: [2][3]isize, model_range: [2][3]isize) ?struct {
    overlap_size: [3]usize,
    range_size: [3]usize,
    model_origin: [3]usize,
    draw_origin: [3]usize,
} {
    const range_size = wgm.cast(usize, wgm.sub(draw_range[1], draw_range[0])).?;

    const overlapping_range: [2][3]isize = .{
        .{
            @max(draw_range[0][0], model_range[0][0]),
            @max(draw_range[0][1], model_range[0][1]),
            @max(draw_range[0][2], model_range[0][2]),
        },
        .{
            @min(draw_range[1][0], model_range[1][0]),
            @min(draw_range[1][1], model_range[1][1]),
            @min(draw_range[1][2], model_range[1][2]),
        },
    };

    const overlap_size = wgm.cast(usize, wgm.sub(overlapping_range[1], overlapping_range[0])) orelse return null;

    const model_offset = wgm.cast(usize, wgm.sub(overlapping_range[0], model_range[0])).?;
    const in_region_offset = wgm.cast(usize, wgm.sub(overlapping_range[0], draw_range[0])).?;

    return .{
        .overlap_size = overlap_size,
        .range_size = range_size,
        .model_origin = model_offset,
        .draw_origin = in_region_offset,
    };
}
