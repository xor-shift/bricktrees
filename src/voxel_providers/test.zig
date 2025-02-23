const std = @import("std");

const wgm = @import("wgm");

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const VoxelProvider = @import("../VoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub fn to_provider() VoxelProvider {
    return .{
        .provider = undefined,

        .should_draw = VoxelProvider.always_draw,
        .should_redraw = foo,

        .draw = Self.draw,
    };
}

pub fn foo(_: *anyopaque, range: [2][3]isize) bool {
    return range[0][1] >= 8 and range[0][1] <= 32 or range[1][1] >= 8 and range[1][1] <= 32;
}

pub fn draw(_: *anyopaque, range: [2][3]isize, storage: []PackedVoxel) void {
    const dummy = PackedVoxel{
        .r = 0xFF,
        .g = 0,
        .b = 0xFF,
        .i = 0x40,
    };
    //@memset(storage, dummy);

    const volume = wgm.cast(usize, wgm.sub(range[1], range[0])).?;
    const base_coords = range[0];

    const t = @as(f64, @floatFromInt(g.time())) / std.time.ns_per_s;

    for (0..volume[2]) |bml_z| for (0..volume[0]) |bml_x| {
        const bml_xz = [2]usize{ bml_x, bml_z };
        const g_xz = wgm.add(wgm.cast(isize, bml_xz).?, [_]isize{
            base_coords[0],
            base_coords[2],
        });
        const dist = wgm.length(wgm.lossy_cast(f64, g_xz));
        const height: isize = @intFromFloat(20 + 10 * @sin(dist / 10 + t));
        const remaining_height: isize = height - base_coords[1];

        if (remaining_height < 0) continue;

        for (0..@min(volume[1], @as(usize, @intCast(remaining_height)))) |bml_y| {
            storage[
                bml_x //
                + bml_y * volume[0] //
                + bml_z * volume[0] * volume[1]
            ] = dummy;
        }
    };
}
