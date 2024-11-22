const Matrix = @import("blas.zig").Matrix;
const Vector = @import("blas.zig").Vector;
const mulmm = @import("blas.zig").mulmm;

pub fn identity(comptime T: type, comptime Dims: usize) Matrix(T, Dims, Dims) {
    var ret: Matrix(T, Dims, Dims) = undefined;

    @memset(&ret.el, 0);
    for (0..Dims) |i| ret.set(i, i, 1);

    return ret;
}

pub fn rotation_matrix_2d(comptime T: type, theta: T) Matrix(T, 2, 2) {
    const sint = @sin(theta);
    const cost = @cos(theta);

    // zig fmt: off
    return .{.el = .{
        cost, -sint,
        sint, cost,
    }};
    // zig fmt: on
}

pub fn rotation_matrix_3d(comptime T: type, yaw: T, pitch: T, roll: T) Matrix(T, 3, 3) {
    const Ret = Matrix(T, 3, 3);

    // zig fmt: off
    const yaw_mat: Ret = .{.el = .{
        @cos(yaw),  0, @sin(yaw),
                  0,  1,           0,
        -@sin(yaw), 0, @cos(yaw),
    }};
    const pitch_mat: Ret = .{.el = .{
        1,         0,          0,
        0, @cos(pitch), -@sin(pitch),
        0, @sin(pitch),  @cos(pitch),
    }};
    const roll_mat: Ret = .{.el = .{
        @cos(roll), -@sin(roll), 0,
        @sin(roll),  @cos(roll), 0,
                 0,           0, 1,
    }};
    // zig fmt: on

    return mulmm(yaw_mat, mulmm(pitch_mat, roll_mat));
}

pub fn rotation_matrix_3d_affine(comptime T: type, yaw: T, pitch: T, roll: T) Matrix(T, 4, 4) {
    const rot = rotation_matrix_3d(T, yaw, pitch, roll);

    // zig fmt: off
    return .{ .el = .{
        rot.el[0], rot.el[1], rot.el[2], 0,
        rot.el[3], rot.el[4], rot.el[5], 0,
        rot.el[6], rot.el[7], rot.el[8], 0,
                0,         0,        0,  1,
    } };
    // zig fmt: on
}
