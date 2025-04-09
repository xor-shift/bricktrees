const std = @import("std");

const dyn = @import("dyn");
const qov = @import("qov");
const wgm = @import("wgm");

const IThing = @import("../IThing.zig");
const IVoxelProvider = @import("../IVoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IVoxelProvider });

file: qov.File,

pub fn should_draw_voxels(self: *Self, range: [2][3]isize) bool {
    _ = self;
    _ = range;
    return false;
}
