const std = @import("std");

const wgm = @import("root.zig");

const Vector = wgm.Vector;
const Matrix = wgm.Matrix;

fn invert2(comptime T: type, mat: Matrix(T, 2, 2)) ?Matrix(T, 2, 2) {
    const a = mat.get(0, 0);
    const b = mat.get(0, 1);
    const c = mat.get(1, 0);
    const d = mat.get(1, 1);

    const D = a * d - b * c;

    if (D == 0) return null;

    return Matrix(T, 2, 2){ .el = .{
        d / D,  -b / D,
        -c / D, a / D,
    } };
}

fn invert3(comptime T: type, mat: Matrix(T, 3, 3)) ?Matrix(T, 3, 3) {
    // fuck it we ball.
    // TODO: I can't be assed with generalization anymore. Remove assumptions about potentially-lazily-evaluated matrices.
    const l = mat.el;

    const D = wgm.det(mat);

    if (D == 0) return null;

    return Matrix(T, 3, 3){ .el = .{
        (l[4] * l[8] - l[5] * l[7]) / D,
        (l[2] * l[7] - l[1] * l[8]) / D,
        (l[1] * l[5] - l[2] * l[4]) / D,
        (l[5] * l[6] - l[3] * l[8]) / D,
        (l[0] * l[8] - l[2] * l[6]) / D,
        (l[2] * l[3] - l[0] * l[5]) / D,
        (l[3] * l[7] - l[4] * l[6]) / D,
        (l[1] * l[6] - l[0] * l[7]) / D,
        (l[0] * l[4] - l[1] * l[3]) / D,
    } };
}

fn invert4(comptime T: type, mat: Matrix(T, 4, 4)) ?Matrix(T, 4, 4) {
    var ret = std.mem.zeroes(Matrix(T, 4, 4));

    const m = mat.el;

    ret.el[0] = m[5] * m[10] * m[15] -
        m[5] * m[11] * m[14] -
        m[9] * m[6] * m[15] +
        m[9] * m[7] * m[14] +
        m[13] * m[6] * m[11] -
        m[13] * m[7] * m[10];

    ret.el[4] = -m[4] * m[10] * m[15] +
        m[4] * m[11] * m[14] +
        m[8] * m[6] * m[15] -
        m[8] * m[7] * m[14] -
        m[12] * m[6] * m[11] +
        m[12] * m[7] * m[10];

    ret.el[8] = m[4] * m[9] * m[15] -
        m[4] * m[11] * m[13] -
        m[8] * m[5] * m[15] +
        m[8] * m[7] * m[13] +
        m[12] * m[5] * m[11] -
        m[12] * m[7] * m[9];

    ret.el[12] = -m[4] * m[9] * m[14] +
        m[4] * m[10] * m[13] +
        m[8] * m[5] * m[14] -
        m[8] * m[6] * m[13] -
        m[12] * m[5] * m[10] +
        m[12] * m[6] * m[9];

    ret.el[1] = -m[1] * m[10] * m[15] +
        m[1] * m[11] * m[14] +
        m[9] * m[2] * m[15] -
        m[9] * m[3] * m[14] -
        m[13] * m[2] * m[11] +
        m[13] * m[3] * m[10];

    ret.el[5] = m[0] * m[10] * m[15] -
        m[0] * m[11] * m[14] -
        m[8] * m[2] * m[15] +
        m[8] * m[3] * m[14] +
        m[12] * m[2] * m[11] -
        m[12] * m[3] * m[10];

    ret.el[9] = -m[0] * m[9] * m[15] +
        m[0] * m[11] * m[13] +
        m[8] * m[1] * m[15] -
        m[8] * m[3] * m[13] -
        m[12] * m[1] * m[11] +
        m[12] * m[3] * m[9];

    ret.el[13] = m[0] * m[9] * m[14] -
        m[0] * m[10] * m[13] -
        m[8] * m[1] * m[14] +
        m[8] * m[2] * m[13] +
        m[12] * m[1] * m[10] -
        m[12] * m[2] * m[9];

    ret.el[2] = m[1] * m[6] * m[15] -
        m[1] * m[7] * m[14] -
        m[5] * m[2] * m[15] +
        m[5] * m[3] * m[14] +
        m[13] * m[2] * m[7] -
        m[13] * m[3] * m[6];

    ret.el[6] = -m[0] * m[6] * m[15] +
        m[0] * m[7] * m[14] +
        m[4] * m[2] * m[15] -
        m[4] * m[3] * m[14] -
        m[12] * m[2] * m[7] +
        m[12] * m[3] * m[6];

    ret.el[10] = m[0] * m[5] * m[15] -
        m[0] * m[7] * m[13] -
        m[4] * m[1] * m[15] +
        m[4] * m[3] * m[13] +
        m[12] * m[1] * m[7] -
        m[12] * m[3] * m[5];

    ret.el[14] = -m[0] * m[5] * m[14] +
        m[0] * m[6] * m[13] +
        m[4] * m[1] * m[14] -
        m[4] * m[2] * m[13] -
        m[12] * m[1] * m[6] +
        m[12] * m[2] * m[5];

    ret.el[3] = -m[1] * m[6] * m[11] +
        m[1] * m[7] * m[10] +
        m[5] * m[2] * m[11] -
        m[5] * m[3] * m[10] -
        m[9] * m[2] * m[7] +
        m[9] * m[3] * m[6];

    ret.el[7] = m[0] * m[6] * m[11] -
        m[0] * m[7] * m[10] -
        m[4] * m[2] * m[11] +
        m[4] * m[3] * m[10] +
        m[8] * m[2] * m[7] -
        m[8] * m[3] * m[6];

    ret.el[11] = -m[0] * m[5] * m[11] +
        m[0] * m[7] * m[9] +
        m[4] * m[1] * m[11] -
        m[4] * m[3] * m[9] -
        m[8] * m[1] * m[7] +
        m[8] * m[3] * m[5];

    ret.el[15] = m[0] * m[5] * m[10] -
        m[0] * m[6] * m[9] -
        m[4] * m[1] * m[10] +
        m[4] * m[2] * m[9] +
        m[8] * m[1] * m[6] -
        m[8] * m[2] * m[5];

    const D = m[0] * ret.el[0] + m[1] * ret.el[4] + m[2] * ret.el[8] + m[3] * ret.el[12];

    if (D == 0) return null;

    return @import("root.zig").divew(ret, D);
}

pub fn inverse(mat: anytype) ?@TypeOf(mat) {
    const Mat = @TypeOf(mat);

    if (Mat.rows != Mat.cols) {
        @compileError("only square matrices are invertible");
    }

    const sl = Mat.rows;

    // handle cases where there are analytical solutions
    switch (sl) {
        0 => @compileError("why are you trying to invert a 0x0 matrix?"),
        1 => {
            const v = mat.get(0, 0);
            if (v == 0) return null;

            return Mat{ .el = .{1 / v} };
        },
        2 => return invert2(Mat.ValueType, mat),
        3 => return invert3(Mat.ValueType, mat),
        4 => return invert4(Mat.ValueType, mat),
        else => {},
    }

    @compileError("inversion of matrices larger than 4x4 is not yet supported");
}

test inverse {
    const Mat1d = Matrix(f64, 1, 1);
    try std.testing.expectEqual(Mat1d{ .el = .{1} }, inverse(Mat1d{ .el = .{1} }));
    try std.testing.expectEqual(Mat1d{ .el = .{0.5} }, inverse(Mat1d{ .el = .{2} }));

    try std.testing.expectEqual(
        Matrix(f64, 2, 2){ .el = .{
            -7, 3,
            5,  -2,
        } },
        inverse(Matrix(f64, 2, 2){ .el = .{
            2, 3,
            5, 7,
        } }),
    );

    try std.testing.expectEqual(
        Matrix(f64, 3, 3){ .el = .{
            1.5,  -4.5, 1,
            -2.5, -3.5, 1,
            1,    4,    -1,
        } },
        inverse(Matrix(f64, 3, 3){ .el = .{
            1,  1,  2,
            3,  5,  8,
            13, 21, 33,
        } }),
    );
}

/// https://stackoverflow.com/a/2625420
pub fn affine_inverse(comptime T: type, mat: Matrix(T, 4, 4)) ?Matrix(T, 4, 4) {
    const m = Matrix(T, 3, 3){ .el = .{
        mat.get(0, 0), mat.get(0, 1), mat.get(0, 2),
        mat.get(1, 0), mat.get(1, 1), mat.get(1, 2),
        mat.get(2, 0), mat.get(2, 1), mat.get(2, 2),
    } };

    const inv_m = inverse(m) orelse return null;

    const b = Vector(T, 3){ .el = .{
        mat.get(0, 3),
        mat.get(1, 3),
        mat.get(2, 3),
    } };

    const ninv_m_b = wgm.mulmm(wgm.negate(inv_m), b);

    return Matrix(T, 4, 4){ .el = .{
        inv_m.get(0, 0), inv_m.get(0, 1), inv_m.get(0, 2), ninv_m_b.get(0, 0),
        inv_m.get(1, 0), inv_m.get(1, 1), inv_m.get(1, 2), ninv_m_b.get(1, 0),
        inv_m.get(2, 0), inv_m.get(2, 1), inv_m.get(2, 2), ninv_m_b.get(2, 0),
        0,               0,               0,               1,
    } };
}

test affine_inverse {
    try std.testing.expectEqual(
        Matrix(f64, 4, 4){ .el = .{
            -2.0,        1.5,          -0.5,  1.0,
            25.0 / 14.0, -53.0 / 28.0, 0.75,  -0.5,
            -1.0 / 14.0, 15.0 / 28.0,  -0.25, -1.5,
            0,           0,            0,     1,
        } },
        affine_inverse(f64, Matrix(f64, 4, 4){ .el = .{
            2,  3,  5,  7,
            11, 13, 17, 21,
            23, 27, 31, 37,
            0,  0,  0,  1,
        } }),
    );
}
