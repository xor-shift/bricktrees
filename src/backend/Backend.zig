const std = @import("std");

const AnyThing = @import("../AnyThing.zig");
const VoxelProvider = @import("../VoxelProvider.zig");

const Self = @This();

const VoxelProviderEntry = struct {
    provider: *VoxelProvider,
};

voxel_providers: std.ArrayList(?VoxelProviderEntry),

view_volume: *const fn (self: *Self) [2][3]isize,
sq_distance_to_center: *const fn (self: *Self, pt: [3]f64) f64,
recenter: *const fn (self: *Self, desired_center: [3]f64) ?[3]f64,

/// You may use the returned index on voxel_providers
pub fn add_voxel_provider(self: *Self, provider: *VoxelProvider) usize {
    const to_add: VoxelProviderEntry = .{
        .provider = provider,
    };

    for (self.voxel_providers.items, 0..) |v, i| if (v == null) {
        self.voxel_providers.items[i] = to_add;
        return i;
    };

    self.voxel_providers.append(to_add) catch @panic("OOM");
    return self.voxel_providers.items.len - 1;
}
