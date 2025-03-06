const std = @import("std");

const wgm = @import("wgm");

// TODO: rename this lol
const this = @This();

pub fn Intersection(comptime T: type) type {
    return struct {
        voxel: [3]isize,
        local_coords: [3]T,
    };
}

pub fn Ray(comptime T: type) type {
    return struct {
        const Self = Ray(T);

        pub const Intersection = this.Intersection(T);

        origin: [3]T,
        direction: [3]T,
        direction_reciprocals: [3]T,

        pub fn init(origin: [3]T, direction: [3]T) Self {
            return .{
                .origin = origin,
                .direction = direction,
                .direction_reciprocals = wgm.div(@as(T, 1), direction),
            };
        }
    };
}

pub fn slab(comptime T: type, extents: [2][3]T, ray: Ray(T)) ?T {
    var t_min: T = 0;
    var t_max: T = std.math.inf(T);

    for (0..3) |d| {
        const t_1 = (extents[0][d] - ray.origin[d]) / ray.direction[d];
        const t_2 = (extents[1][d] - ray.origin[d]) / ray.direction[d];

        t_min = @min(@max(t_1, t_min), @max(t_2, t_min));
        t_max = @max(@min(t_1, t_max), @min(t_2, t_max));
    }

    if (t_min > t_max) return null;

    return t_min;
}

test slab {
    try std.testing.expectEqual(1.0099504938362078, slab(f64, .{
        [_]f64{ -1, -1, 1 },
        [_]f64{ 1, 1, 2 },
    }, Ray(f64).init(
        .{ 0, 0, 0 },
        wgm.normalized([_]f64{ 0.1, 0.1, 1 }),
    )));
}
