const std = @import("std");

const wgm = @import("root.zig");

const Matrix = wgm.Matrix;
const Vector = wgm.Vector;

const He = wgm.Helper;

fn SquareMat(comptime T: type, comptime dims: usize) type {
    return Matrix(T, dims, dims);
}

const mulmm = wgm.mulmm;
const transpose = wgm.transpose;

pub fn identity(comptime T: type, comptime dims: usize) SquareMat(T, dims) {
    const Ret = SquareMat(T, dims);
    const H = He(Ret);

    var ret: Ret = undefined;
    @memset(H.fp(&ret), 0);
    for (0..dims) |i| H.set(&ret, i, i, 1);

    return ret;
}

pub fn from_homogenous(vec: anytype) Vector(He(@TypeOf(vec)).T, He(@TypeOf(vec)).rows - 1) {
    const H = He(@TypeOf(vec));
    const Ret = Vector(H.T, H.rows - 1);
    const HR = He(Ret);

    var ret: Ret = undefined;
    @memcpy(HR.fp(&ret), H.cfp(&vec)[0 .. H.rows - 1]);

    return wgm.div(ret, H.get(&vec, H.rows - 1, 0));
}

test from_homogenous {
    try std.testing.expectEqual([3]usize{ 1, 2, 3 }, from_homogenous([4]usize{ 2, 4, 6, 2 }));
}

pub fn pad_affine(mat: anytype) Matrix(He(@TypeOf(mat)).T, He(@TypeOf(mat)).rows + 1, He(@TypeOf(mat)).cols + 1) {
    const H = He(@TypeOf(mat));
    const Ret = Matrix(H.T, H.rows + 1, H.cols + 1);
    const RH = He(Ret);

    var ret = std.mem.zeroes(Ret);
    for (0..H.cols) |c| @memcpy(RH.p(&ret)[c][0 .. RH.rows - 1], &H.cp(&mat)[c]);
    RH.set(&ret, H.rows, H.cols, 1);

    return ret;
}

pub fn rotation_2d(comptime T: type, theta: T) Matrix(T, 2, 2) {
    const sint = @sin(theta);
    const cost = @cos(theta);

    return transpose([2][2]T{
        cost, -sint,
        sint, cost,
    });
}

pub fn rotate_x_3d(comptime T: type, r: T) [3][3]T {
    return transpose([3][3]T{
        .{ 1, 0, 0 },
        .{ 0, @cos(r), -@sin(r) },
        .{ 0, @sin(r), @cos(r) },
    });
}

pub fn rotate_y_3d(comptime T: type, r: T) [3][3]T {
    return transpose([3][3]T{
        .{ @cos(r), 0, @sin(r) },
        .{ 0, 1, 0 },
        .{ -@sin(r), 0, @cos(r) },
    });
}

pub fn rotate_z_3d(comptime T: type, r: T) [3][3]T {
    return transpose([3][3]T{
        .{ @cos(r), -@sin(r), 0 },
        .{ @sin(r), @cos(r), 0 },
        .{ 0, 0, 1 },
    });
}

pub fn translate_3d(vec: anytype) SquareMat(He(@TypeOf(vec)).T, He(@TypeOf(vec)).rows + 1) {
    const H = He(@TypeOf(vec));
    const Ret = SquareMat(H.T, H.rows + 1);
    const HR = He(Ret);

    std.debug.assert(H.rows == 3);
    std.debug.assert(H.cols == 1);

    var ret = identity(H.T, H.rows + 1);
    for (0..H.rows) |r| HR.set(&ret, r, H.rows, H.get(&vec, r, 0));

    return ret;
}

pub fn scale_3d(vec: anytype) SquareMat(He(@TypeOf(vec)).T, He(@TypeOf(vec)).rows) {
    const H = He(@TypeOf(vec));
    const Ret = SquareMat(H.T, H.rows);
    const HR = He(Ret);

    std.debug.assert(H.rows == 3);
    std.debug.assert(H.cols == 1);

    var ret = std.mem.zeroes(Ret);
    for (0..H.rows) |r| HR.set(&ret, r, r, H.get(&vec, r, 0));

    return ret;
}

pub fn scale_3d_affine(vec: anytype) SquareMat(He(@TypeOf(vec)).T, He(@TypeOf(vec)).rows + 1) {
    return pad_affine(scale_3d(vec));
}

pub fn ortho(near: anytype, far: @TypeOf(near)) SquareMat(He(@TypeOf(near)).T, 4) {
    const H = He(@TypeOf(near));
    const T = H.T;

    std.debug.assert(H.rows == 3);
    std.debug.assert(H.cols == 1);

    const translation = translate_3d([3]T{
        -(H.x(near) + H.x(far)) / 2,
        -(H.y(near) + H.y(far)) / 2,
        -H.z(near),
    });

    const scale = scale_3d_affine([3]T{
        2 / (H.x(far) - H.x(near)),
        2 / (H.y(far) - H.y(near)),
        1 / (H.z(far) - H.z(near)),
    });

    return mulmm(scale, translation);
}

pub fn z_scale(comptime T: type, n: T, f: T) Matrix(T, 4, 4) {
    return transpose([4][4]T{
        .{ n, 0, 0, 0 },
        .{ 0, n, 0, 0 },
        .{ 0, 0, n + f, -n * f },
        .{ 0, 0, 1, 0 },
    });
}

pub fn perspective(near: anytype, far: @TypeOf(near)) SquareMat(He(@TypeOf(near)).T, 4) {
    const H = He(@TypeOf(near));

    return mulmm(ortho(near, far), z_scale(H.T, H.z(near), H.z(far)));
}

pub fn perspective_fov(comptime T: type, near: T, far: T, fovy: T, aspect: T) Matrix(T, 4, 4) {
    const angle = fovy / 2;
    const ymax = near * @tan(angle);
    const xmax = ymax * aspect;

    const near_vec = [3]T{
        -xmax,
        -ymax,
        near,
    };

    const far_vec = [3]T{
        xmax,
        ymax,
        far,
    };

    if (@inComptime()) @setEvalBranchQuota(1500);
    return perspective(near_vec, far_vec);
}
