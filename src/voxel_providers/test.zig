const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const IThing = @import("../IThing.zig");
const IVoxelProvider = @import("../IVoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IVoxelProvider });

pub fn init() !Self {
    return .{};
}

pub fn should_draw_voxels(_: *Self, range: [2][3]isize) bool {
    _ = range;
    return false;
}

pub fn should_redraw_voxels(_: *Self, range: [2][3]isize) bool {
    if (true) return false;
    return range[0][1] >= 10 and range[0][1] <= 30 or range[1][1] >= 10 and range[1][1] <= 30;
}

pub fn draw_voxels(_: *Self, range: [2][3]isize, storage: []PackedVoxel) void {
    if (true) return;
    const volume = wgm.cast(usize, wgm.sub(range[1], range[0])).?;
    const base_coords = range[0];

    // const t = @as(f64, @floatFromInt(g.time())) / std.time.ns_per_s;
    const t: f64 = 1.0;

    for (0..volume[2]) |bml_z| for (0..volume[0]) |bml_x| {
        const bml_xz = [2]usize{ bml_x, bml_z };
        const g_xz = wgm.add(wgm.cast(isize, bml_xz).?, [_]isize{
            base_coords[0],
            base_coords[2],
        });
        const dist = wgm.length(wgm.lossy_cast(f64, g_xz));
        const height: isize = @intFromFloat(20 + 10 * @sin(dist / 10 - t));
        const remaining_height: isize = height - base_coords[1];

        if (remaining_height < 0) continue;

        for (0..@min(volume[1], @as(usize, @intCast(remaining_height)))) |bml_y| {
            storage[
                bml_x //
                + bml_y * volume[0] //
                + bml_z * volume[0] * volume[1]
            ] = (Voxel{
                .Normal = .{
                    .rougness = 1.0,
                    .rgb = .{ 0.1, 0.2, 0.3 },
                },
            }).pack();
        }
    };
}
