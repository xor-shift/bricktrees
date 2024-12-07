const std = @import("std");

const blas = @import("../blas/blas.zig");

/// max mip size in number of elements (divide by 8 for the compact form)
pub const u8_mip_size = 8 + 8 * 8 + 8 * 8 * 8 + 8 * 8 * 8 * 8 + 8 * 8 * 8 * 8 * 8;

/// the reduced mip size
pub const u64_mip_size = 64 + 64 * 64;

pub fn old_u8_mipmap_indices(coords: blas.Vec3uz) [5]usize {
    var ret: [5]usize = undefined;

    var mip_offset: usize = 0;
    for (0..5) |i| {
        const shift = 5 - i;

        const level_x = (coords.x() >> @as(u6, @intCast(shift)));
        const level_y = (coords.y() >> @as(u6, @intCast(shift)));
        const level_z = (coords.z() >> @as(u6, @intCast(shift)));

        const level_offset =
            (level_z << @as(u6, @intCast((i + 1) * 2))) |
            (level_y << @as(u6, @intCast(i + 1))) |
            level_x;

        ret[i] = mip_offset + level_offset;

        const local_mip_offset = @as(usize, 1) << @as(u6, @intCast(i * 3 + 3));

        mip_offset += local_mip_offset;
    }

    return ret;
}

pub fn u8_mipmap_indices(coords: blas.Vec3uz) [5]usize {
    var ret: [5]usize = undefined;

    var mip_offset: usize = 0;
    for (0..5) |i| {
        const level_x = (coords.x() >> @as(u6, @intCast(i + 1)));
        const level_y = (coords.y() >> @as(u6, @intCast(i + 1)));
        const level_z = (coords.z() >> @as(u6, @intCast(i + 1)));

        const bits_per_axis = @as(u6, @intCast(5 - i));
        const level_offset =
            (level_z << (bits_per_axis * 2)) |
            (level_y << bits_per_axis) |
            level_x;

        ret[i] = mip_offset + level_offset;

        const level_size = @as(usize, 1) << (3 * bits_per_axis);
        mip_offset += level_size;
    }

    return ret;
}

test u8_mipmap_indices {
    const table = [_]std.meta.Tuple(&.{ blas.Vec3uz, [5]usize }){
        .{ blas.vec3uz(0, 0, 0), [5]usize{ 0, 8, 72, 584, 4680 } },
        .{ blas.vec3uz(2, 0, 0), [5]usize{ 0, 8, 72, 584, 4681 } },
    };

    for (0.., table) |i, test_pair| {
        const coords = test_pair.@"0";
        const expected = test_pair.@"1";
        const got = u8_mipmap_indices(coords);
        if (!std.mem.eql(usize, &expected, &got)) {
            std.log.err("test #{d}, coordinates ({d}, {d}, {d}): expected: {any}, got: {any}", .{
                i,        coords.x(), coords.y(), coords.z(),
                expected, got,
            });
        }
    }
}
