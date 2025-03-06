const std = @import("std");

const dyn = @import("dyn");

const IVoxelProvider = @import("../IVoxelProvider.zig");

const Self = @This();

pub const DynStatic = dyn.IFaceStuff(Self);

/// Returns the minimum and the maximum voxel coordinates.
/// The range is exclusive and the size can be 0.
pub const view_volume = fn (self: dyn.Fat(*Self)) [2][3]isize;

/// Returns the square distance from the center of the view volume of a given
/// point.
pub const sq_distance_to_center = fn (self: dyn.Fat(*Self), pt: [3]f64) f64;

pub const recenter = fn (self: dyn.Fat(*Self), desired_center: [3]f64) ?[3]f64;

pub fn options_ui(_: dyn.Fat(*Self)) void {}
