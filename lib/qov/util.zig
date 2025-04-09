const std = @import("std");

const wgm = @import("wgm");

pub fn g_to_gl(
    global_coords: [3]isize,
    origin: [3]isize,
    dims: [3]usize,
) ?[3]usize {
    const local_coords = wgm.sub(global_coords, origin);

    const dims_signed = wgm.cast(isize, dims).?;

    if (wgm.compare(.some, local_coords, .greater_than_equal, dims_signed) or //
        wgm.compare(.some, local_coords, .less_than, [_]isize{0} ** 3))
    {
        return null;
    }

    return wgm.cast(usize, local_coords).?;
}

pub fn shift_grid(
    comptime T: type,
    delta: [3]isize,
    dims: [3]usize,
    default: T,
    grid: []T,
) void {
    // if this is deemed too slow, take a look at how the brickmap backend
    // handles its grid shifts. (which it simply does not handle. remember,
    // kids: the best way to speed things up is to do less things)

    for (0..dims[2]) |z| for (0..dims[1]) |y| for (0..dims[0]) |x| {
        const gl_s_out_coords = [_]usize{
            if (delta[0] < 0) x else dims[0] - x - 1,
            if (delta[1] < 0) y else dims[1] - y - 1,
            if (delta[2] < 0) z else dims[2] - z - 1,
        };
        const out_idx = wgm.to_idx(gl_s_out_coords, dims);

        const g_s_out_coords = wgm.cast(isize, gl_s_out_coords).?;
        const g_s_in_coords = wgm.add(g_s_out_coords, wgm.negate(delta));
        if (wgm.compare(.some, g_s_in_coords, .greater_than_equal, wgm.cast(isize, dims).?) or //
            wgm.compare(.some, g_s_in_coords, .less_than, [_]isize{0} ** 3))
        {
            grid[out_idx] = default;
            continue;
        }

        const gl_s_in_coords = wgm.cast(usize, g_s_in_coords).?;

        const in_idx = wgm.to_idx(gl_s_in_coords, dims);

        grid[out_idx] = grid[in_idx];
    };
}

test shift_grid {
    var grid = [_]i32{
        0,  0,  0,  0, 0, 0,
        0,  0,  0,  0, 0, 0,
        0,  0,  0,  0, 0, 0,
        0,  1,  2,  3, 0, 0,
        -1, -2, -3, 0, 0, 0,
        0,  0,  0,  0, 0, 0,
    };
    shift_grid(i32, .{ 3, -3, 0 }, .{ 6, 6, 1 }, -4, &grid);
    try std.testing.expectEqualSlices(
        i32,
        &[_]i32{
            -4, -4, -4, 0,  1,  2,
            -4, -4, -4, -1, -2, -3,
            -4, -4, -4, 0,  0,  0,
            -4, -4, -4, -4, -4, -4,
            -4, -4, -4, -4, -4, -4,
            -4, -4, -4, -4, -4, -4,
        },
        &grid,
    );
}

pub fn resize_grid(
    comptime T: type,
    default: T,
    old_grid: []const T,
    old_dims: [3]usize,
    new_dims: [3]usize,
    alloc: std.mem.Allocator,
) ![]T {
    const sz = new_dims[2] * new_dims[1] * new_dims[0];
    const new_grid = try alloc.alloc(T, sz);
    @memset(new_grid, default);
    errdefer alloc.free(new_grid);

    for (0..@min(old_dims[2], new_dims[2])) |z| for (0..@min(old_dims[1], new_dims[1])) |y| {
        const out_start = z * new_dims[1] * new_dims[0] + y * new_dims[0];
        const out_len = @min(old_dims[0], new_dims[0]);
        const in_start = z * old_dims[1] * old_dims[0] + y * old_dims[0];

        @memcpy(
            new_grid[out_start .. out_start + out_len],
            old_grid[in_start .. in_start + out_len],
        );
    };

    return new_grid;
}

test resize_grid {
    const alloc = std.testing.allocator;

    const grid = try resize_grid(
        i32,
        -1,
        &.{
            1, 2, 3,
            4, 5, 6,
        },
        .{ 3, 2, 1 },
        .{ 4, 3, 2 },
        alloc,
    );
    defer alloc.free(grid);

    try std.testing.expectEqualSlices(i32, &.{
        1,  2,  3,  -1,
        4,  5,  6,  -1,
        -1, -1, -1, -1,

        -1, -1, -1, -1,
        -1, -1, -1, -1,
        -1, -1, -1, -1,
    }, grid);
}
