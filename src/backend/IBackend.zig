const std = @import("std");

const dyn = @import("dyn");

const IVoxelProvider = @import("../IVoxelProvider.zig");

const Self = @This();

pub const DynStatic = dyn.IFaceStuff(Self);

/// Returns the minimum and the maximum voxel coordinates.
/// The range is exclusive and the size can be 0.
pub const view_volume = fn (self: dyn.Fat(*Self)) [2][3]isize;

/// Returns the point in space representing the origin
pub const get_origin = fn (self: dyn.Fat(Self)) [3]f64;

/// Tries to change the center to be as close to the passed `desired_center` as
/// possible. Returns the origin of the viewing volume, which might not have
/// changed.
pub const recenter = fn (self: dyn.Fat(*Self), desired_center: [3]f64) void;

pub const configure = fn(self: dyn.Fat(*Self), config: BackendConfig) anyerror!void;

pub fn options_ui(_: dyn.Fat(*Self)) void {}

pub const BackendConfig = struct {
    /// The largest allocated buffer by the backend will be no larger than this.
    buffer_size: usize = @as(usize, 1) << 31 - 1,

    /// Enforced on a best-effort basis.
    desied_view_volume_size: [3]usize,
};

