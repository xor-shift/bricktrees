const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const wgpu = @import("gfx").wgpu;

const PackedVoxel = @import("qov").PackedVoxel;

const Self = @This();

pub const DynStatic = dyn.IFaceStuff(Self);

pub const RegionStatus = enum {
    empty,
    want_draw,
    want_redraw,
};

pub const DrawKind = enum {
    cpu,
    gpu,
};

/// Guaranteed to be called from the render thread.
///
/// This is so that the voxel provider locks any locks that need to be locked
/// before `should_redraw` and `draw` are called.
pub fn voxel_draw_start(_: dyn.Fat(*Self)) void {}

pub fn voxel_draw_end(_: dyn.Fat(*Self)) void {}

pub fn status_for_region(_: dyn.Fat(*Self), range: VoxelRange) RegionStatus {
    _ = range;
    return .want_draw;
}

pub fn draw_kind(_: dyn.Fat(*Self), range: VoxelRange) DrawKind {
    _ = range;
    return .cpu;
}

pub const VoxelRange = struct {
    origin: [3]isize,
    volume: [3]usize,
};

/// Might be called concurrently.
/// Range is inclusive.
pub const draw_voxels = fn (_: dyn.Fat(*Self), range: VoxelRange, storage: []PackedVoxel) void;

pub const OverlapInfo = struct {
    local_origin: [3]usize,
    global_origin: [3]isize,
    volume: [3]usize,
};

pub fn overlap_info(draw_range: VoxelRange, model_range: VoxelRange) ?OverlapInfo {
    if (wgm.compare(.some, draw_range.volume, .equal, [_]usize{0} ** 3)) return null;
    if (wgm.compare(.some, model_range.volume, .equal, [_]usize{0} ** 3)) return null;

    const global_origin = wgm.max(draw_range.origin, model_range.origin);

    const draw_max = wgm.add(draw_range.origin, wgm.cast(isize, wgm.sub(draw_range.volume, 1)).?);
    const model_max = wgm.add(model_range.origin, wgm.cast(isize, wgm.sub(model_range.volume, 1)).?);
    const true_max = wgm.min(draw_max, model_max);
    const volume = wgm.cast(usize, wgm.add(wgm.sub(true_max, global_origin), 1)) orelse return null;

    if (wgm.compare(.some, volume, .equal, [_]usize{0} ** 3)) return null;

    return .{
        .local_origin = wgm.cast(usize, wgm.sub(global_origin, model_range.origin)).?,
        .global_origin = global_origin,
        .volume = volume,
    };
}

test overlap_info {
    try std.testing.expectEqual(OverlapInfo{
        .local_origin = .{ 0, 0, 2 },
        .global_origin = .{ 1, 2, 3 },
        .volume = .{ 2, 3, 1 }, // 2 4 3 incl.
    }, overlap_info(.{
        .origin = .{ 1, 2, 3 },
        .volume = .{ 2, 3, 5 }, // 2 4 7 incl.
    }, .{
        .origin = .{ 1, 2, 1 },
        .volume = .{ 5, 3, 3 }, // 5 4 3 incl.
    }));
}
