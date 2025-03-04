const std = @import("std");

const wgm = @import("wgm");

const PackedVoxel = @import("voxel.zig").PackedVoxel;

const VoxelProvider = @This();

/// Guaranteed to be called from the render thread.
///
/// This is so that the voxel provider locks any locks that need to be locked
/// before `should_redraw` and `draw` are called.
render_start: *const fn (self_arg: *VoxelProvider) void,

render_end: *const fn (self_arg: *VoxelProvider) void,

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is _currently_ occupied by the object or objects this provider represents
should_draw: *const fn (self_arg: *VoxelProvider, range: [2][3]isize) bool,

/// Might be called concurrently
///
/// This function should return true in the following circumstances:
/// - The given range is currently occupied _AND_ used not to be occupied during the previous render
/// - The given range is not occupied _AND_ used to be occupied during the previous render
/// - The given range was occupied, is occupied, and the contents of it changed since the previous render
should_redraw: *const fn (self_arg: *VoxelProvider, range: [2][3]isize) bool,

/// Might be called concurrently
draw: *const fn (self_arg: *VoxelProvider, range: [2][3]isize, storage: []PackedVoxel) void,

pub fn mk_vtable(comptime Concrete: type) VoxelProvider {
    return @import("vtable_utils.zig").mk_vtable(Concrete, VoxelProvider, "voxel_provider", struct {
        pub fn render_start(_: *VoxelProvider) void {}
        pub fn render_end(_: *VoxelProvider) void {}

        pub fn should_draw(_: *VoxelProvider, _: [2][3]isize) bool {
            return true;
        }

        pub fn should_redraw(_: *VoxelProvider, _: [2][3]isize) bool {
            return false;
        }
    });
}

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
