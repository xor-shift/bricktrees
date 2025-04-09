const std = @import("std");

fn cross(comptime T: type, a: @Vector(3, T), b: @Vector(3, T)) @Vector(3, T) {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

/// Returns whether there's an intersection along axis `axis` between:
///  - the triangle `triangle`
///  - the AABB from (-0.5, -0.5, -0.5) to (0.5, 0.5, 0.5)
fn single_test(comptime T: type, triangle: [3]@Vector(3, T), axis: @Vector(3, T)) bool {
    const tri_projected = .{
        @reduce(.Add, triangle[0] * axis),
        @reduce(.Add, triangle[1] * axis),
        @reduce(.Add, triangle[2] * axis),
    };

    const min_ptri = @min(tri_projected[0], @min(tri_projected[1], tri_projected[2]));
    const max_ptri = @max(tri_projected[0], @max(tri_projected[1], tri_projected[2]));

    const r = 0.5 * (@abs(axis[0]) + @abs(axis[1]) + @abs(axis[2]));

    //return min_ptri < r and max_ptri >= -r;
    return @max(-max_ptri, min_ptri) <= r;
}

test single_test {
    const test_tri: [3]@Vector(3, f32) = .{
        .{ -2.03920, -4.50110, 0.55454 },
        .{ -0.36048, -2.68340, 0.43145 },
        .{ -1.27010, -1.39480, 0.43145 },
    };

    try std.testing.expect(single_test(f32, test_tri, .{ 1, 0, 0 }));
    try std.testing.expect(!single_test(f32, test_tri, .{ 0, 1, 0 }));
    try std.testing.expect(single_test(f32, test_tri, .{ 0, 0, 1 }));
}

/// ඞඞඞඞඞඞඞඞඞඞ
/// ඞ ╭───╮  ඞ
/// ඞ │ ╭─┴─╮ඞ
/// ඞ │ ╰─┬─╯ඞ
/// ඞ │   │  ඞ
/// ඞ │ │ │  ඞ
/// ඞ ╰─┴─╯  ඞ
/// ඞඞඞඞඞඞඞඞඞඞ
/// https://fileadmin.cs.lth.se/cs/Personal/Tomas_Akenine-Moller/code/tribox_tam.pdf
pub fn intersects_adjusted(comptime T: type, triangle: [3]@Vector(3, T)) bool {
    if (!single_test(T, triangle, .{ 1, 0, 0 })) return false;
    if (!single_test(T, triangle, .{ 0, 1, 0 })) return false;
    if (!single_test(T, triangle, .{ 0, 0, 1 })) return false;

    const edges = .{
        triangle[1] - triangle[0],
        triangle[2] - triangle[1],
        triangle[0] - triangle[2],
    };

    const normal = cross(T, edges[0], edges[1]);

    if (!single_test(T, triangle, normal)) return false;

    if (!single_test(T, triangle, cross(T, .{ 1, 0, 0 }, edges[0]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 1, 0, 0 }, edges[1]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 1, 0, 0 }, edges[2]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 1, 0 }, edges[0]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 1, 0 }, edges[1]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 1, 0 }, edges[2]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 0, 1 }, edges[0]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 0, 1 }, edges[1]))) return false;
    if (!single_test(T, triangle, cross(T, .{ 0, 0, 1 }, edges[2]))) return false;

    return true;
}

test intersects_adjusted {
    const test_tri_0: [3]@Vector(3, f32) = .{
        .{ -2.03920 / 2.0, -4.50110 / 2.0, 0.55454 / 2.0 },
        .{ -0.36048 / 2.0, -2.68340 / 2.0, 0.43145 / 2.0 },
        .{ -1.27010 / 2.0, -1.39480 / 2.0, 0.43145 / 2.0 },
    };

    try std.testing.expect(!intersects_adjusted(f32, test_tri_0));

    const test_tri_1: [3]@Vector(3, f32) = .{
        .{ -1.231000 / 2.0, -4.501100 / 2.0, 0.018594 / 2.0 },
        .{ -0.360480 / 2.0, -1.656700 / 2.0, 0.431450 / 2.0 },
        .{ -1.205700 / 2.0, -0.488700 / 2.0, 0.484480 / 2.0 },
    };

    try std.testing.expect(intersects_adjusted(f32, test_tri_1));
}

pub fn intersects_adjusted_fast(
    comptime T: type,
    triangle: [3]@Vector(3, T),
    comptime assert_bounded: bool,
) bool {
    const axis_check = struct {
        fn aufruf(tri: [3]@Vector(3, T), axis: usize) bool {
            const tri_projected = .{
                tri[0][axis],
                tri[1][axis],
                tri[2][axis],
            };

            const min_ptri = @min(tri_projected[0], @min(tri_projected[1], tri_projected[2]));
            const max_ptri = @max(tri_projected[0], @max(tri_projected[1], tri_projected[2]));

            return @max(-max_ptri, min_ptri) <= 0.5;
        }
    }.aufruf;

    if (!assert_bounded) {
        if (!axis_check(triangle, 0)) return false;
        if (!axis_check(triangle, 1)) return false;
        if (!axis_check(triangle, 2)) return false;
    }

    if (false) {
        const slice = .{
            triangle[0][0],
            triangle[0][1],
            triangle[0][2],
            triangle[1][0],
            triangle[1][1],
            triangle[1][2],
            triangle[2][0],
            triangle[2][1],
            triangle[2][2],
        };

        const min, const max = std.mem.minMax(f32, &slice);

        if (min >= 1 or max < -1) return false;
    }

    const edge_0 = triangle[1] - triangle[0];
    const edge_1 = triangle[2] - triangle[1];
    // const edge_2 = triangle[0] - triangle[2];

    const normal = cross(T, edge_0, edge_1);

    if (!single_test(T, triangle, normal)) return false;

    const cross_check = struct {
        fn aufruf(tri: [3]@Vector(3, T), comptime edge: u32, comptime axis: usize) bool {
            const edges = .{
                tri[1] - tri[0],
                tri[2] - tri[1],
                tri[0] - tri[2],
            };

            const ev = edges[edge];

            const prav: @Vector(3, T) = switch (axis) {
                0 => .{ 0, -ev[2], ev[1] },
                1 => .{ ev[2], 0, -ev[0] },
                2 => .{ -ev[1], ev[0], 0 },
                else => @compileError("bad axis"),
            };

            const tri_projected = .{
                @reduce(.Add, tri[0] * prav),
                @reduce(.Add, tri[1] * prav),
                @reduce(.Add, tri[2] * prav),
            };

            const bi_projected = switch (edge) {
                0 => .{ tri_projected[1], tri_projected[2] },
                1 => .{ tri_projected[2], tri_projected[0] },
                2 => .{ tri_projected[0], tri_projected[1] },
                else => @compileError("bad edge"),
            };

            const r = (@abs(prav[0]) + @abs(prav[1]) + @abs(prav[2])) * 0.5;

            const min = @min(bi_projected[0], bi_projected[1]);
            const max = @max(bi_projected[0], bi_projected[1]);
            return @max(-max, min) <= r;
        }
    }.aufruf;

    if (!cross_check(triangle, 0, 0)) return false;
    if (!cross_check(triangle, 1, 0)) return false;
    if (!cross_check(triangle, 2, 0)) return false;
    if (!cross_check(triangle, 0, 1)) return false;
    if (!cross_check(triangle, 1, 1)) return false;
    if (!cross_check(triangle, 2, 1)) return false;
    if (!cross_check(triangle, 0, 2)) return false;
    if (!cross_check(triangle, 1, 2)) return false;
    if (!cross_check(triangle, 2, 2)) return false;

    return true;
}

test "intersection regression" {
    const seed: u64 = 0xDEADBEEFCAFEBABE;
    var rng = std.rand.Xoshiro256.init(seed);
    const rand = rng.random();

    const no_tests: usize = 1024;

    var got = std.bit_set.ArrayBitSet(usize, no_tests).initEmpty();
    const expected: std.bit_set.ArrayBitSet(usize, no_tests) = .{ .masks = .{ 2289183747997696, 396483895123509264, 1152925902653394954, 586066481020666112, 576460763313471808, 2341889408216662144, 17596481015816, 5802926053018181760, 70386360254726, 424962588704772, 184649790730027520, 1153062242096924707, 289708154139312128, 17179869312, 81083210651412480, 144867323085934660 } };

    for (0..no_tests) |i| {
        const mult: @Vector(3, f32) = @splat(3.141592653589793238462643383279 / 2.0);

        const triangle: [3]@Vector(3, f32) = .{
            @Vector(3, f32){ rand.float(f32), rand.float(f32), rand.float(f32) } * mult,
            @Vector(3, f32){ rand.float(f32), rand.float(f32), rand.float(f32) } * mult,
            @Vector(3, f32){ rand.float(f32), rand.float(f32), rand.float(f32) } * mult,
        };

        const res = intersects_adjusted(f32, triangle);
        try std.testing.expectEqual(expected.isSet(i), res);

        const fast_res = intersects_adjusted_fast(f32, triangle);
        try std.testing.expectEqual(res, fast_res);

        if (res) got.set(i);
    }
}

pub fn intersects(comptime T: type, triangle: [3]@Vector(3, T), aabb: [2]@Vector(3, T)) bool {
    const half = @Vector(3, f32){ 0.5, 0.5, 0.5 };
    const origin = aabb[0] + (aabb[1] - aabb[0]) * half;
    const extent = aabb[1] - aabb[0];

    return intersects_adjusted(f32, .{
        (triangle[0] - origin - half) / extent,
        (triangle[1] - origin - half) / extent,
        (triangle[2] - origin - half) / extent,
    });
}

test intersects {
    try std.testing.expect(intersects(f32, .{
        .{ 1.5, 1.5, 1.5 },
        .{ 1.5, 1.5, 3.5 },
        .{ 3.5, 1.5, 1.5 },
    }, .{
        .{ 1, 1, 1 },
        .{ 2, 2, 2 },
    }));
}

pub fn intersects_voxel(
    comptime T: type,
    triangle: [3]@Vector(3, T),
    vox: @Vector(3, T),
    comptime assert_bounded: bool,
) bool {
    return intersects_adjusted_fast(T, .{
        (triangle[0] - vox - @Vector(3, T){ 0.5, 0.5, 0.5 }),
        (triangle[1] - vox - @Vector(3, T){ 0.5, 0.5, 0.5 }),
        (triangle[2] - vox - @Vector(3, T){ 0.5, 0.5, 0.5 }),
    }, assert_bounded);
}
