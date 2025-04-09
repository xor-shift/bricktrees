const std = @import("std");

const dyn = @import("dyn");
const qov = @import("qov");
const wgm = @import("wgm");

const PackedVoxel = qov.PackedVoxel;
const Voxel = qov.Voxel;

const IThing = @import("../IThing.zig");
const IVoxelProvider = @import("../IVoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IVoxelProvider });

pub fn init() !Self {
    return .{};
}

pub fn status_for_region(_: *Self, range: IVoxelProvider.VoxelRange) IVoxelProvider.RegionStatus {
    const min = range.origin[0];
    const max = range.origin[1] + @as(isize, @intCast(range.volume[1]));

    if (min >= 10 and min <= 30 or //
        max >= 10 and max <= 30)
    {
        return .want_redraw;
    }

    return .want_draw;
}

pub fn draw_voxels(_: *Self, range: IVoxelProvider.VoxelRange, storage: []PackedVoxel) void {
    if (false) return;

    // const t = @as(f64, @floatFromInt(g.time())) / std.time.ns_per_s;
    const t: f64 = 1.0;

    for (0..range.volume[2]) |bml_z| for (0..range.volume[0]) |bml_x| {
        const bml_xz = [2]usize{ bml_x, bml_z };
        const g_xz = wgm.add(wgm.cast(isize, bml_xz).?, [_]isize{
            range.origin[0],
            range.origin[2],
        });
        const dist = wgm.length(wgm.lossy_cast(f64, g_xz));
        const height: isize = @intFromFloat(20 + 10 * @sin(dist / 10 - t));
        const remaining_height: isize = height - range.origin[1];

        if (remaining_height < 0) continue;

        for (0..@min(range.volume[1], @as(usize, @intCast(remaining_height)))) |bml_y| {
            storage[wgm.to_idx([_]usize{ bml_x, bml_y, bml_z }, range.volume)] = (Voxel{
                .Normal = .{
                    .rougness = 1.0,
                    .rgb = .{ 0.1, 0.2, 0.3 },
                },
            }).pack();
        }
    };
}
