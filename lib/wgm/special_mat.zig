const std = @import("std");

const wgm = @import("root.zig");

const Traits = wgm.Traits;

const Vector = wgm.Vector;
const Matrix = wgm.Matrix;

const mulmm = wgm.mulmm;

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

    return mulmm(roll_mat, mulmm(pitch_mat, yaw_mat));
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

pub fn translate_3d(comptime T: type, translation: Vector(T, 3)) Matrix(T, 4, 4) {
    return Matrix(T, 4, 4){ .el = .{
        1, 0, 0, translation.get(0, 0),
        0, 1, 0, translation.get(1, 0),
        0, 0, 1, translation.get(2, 0),
        0, 0, 0, 1,
    } };
}

test translate_3d {
    try std.testing.expectEqual(
        Matrix(isize, 4, 4){ .el = .{
            1, 0, 0, 1,
            0, 1, 0, 2,
            0, 0, 1, -3,
            0, 0, 0, 1,
        } },
        translate_3d(isize, .{ .el = .{ 1, 2, -3 } }),
    );
}

pub fn scale_3d_affine(comptime T: type, scale: Vector(T, 3)) Matrix(T, 4, 4) {
    return Matrix(T, 4, 4){ .el = .{
        scale.x(), 0,         0,         0,
        0,         scale.y(), 0,         0,
        0,         0,         scale.z(), 0,
        0,         0,         0,         1,
    } };
}

pub fn ortho(comptime T: type, near: Vector(T, 3), far: Vector(T, 3)) Matrix(T, 4, 4) {
    const translation = translate_3d(T, Vector(T, 3){ .el = .{
        -(near.x() + far.x()) / 2,
        -(near.y() + far.y()) / 2,
        -near.z(),
    } });

    const scale = scale_3d_affine(T, Vector(T, 3){ .el = .{
        2 / (far.x() - near.x()),
        2 / (far.y() - near.y()),
        1 / (far.z() - near.z()),
    } });

    return mulmm(scale, translation);
}

pub fn z_scale(comptime T: type, n: T, f: T) Matrix(T, 4, 4) {
    // const fl = 1.0;
    // const r = 1.0;

    // return .{ .el = .{
    //     fl,  0.0,    0.0,              0.0,
    //     0.0, fl * r, 0.0,              0.0,
    //     0.0, 0.0,    f / (f - n),      1.0,
    //     0.0, 0.0,    -f * n / (f - n), 0.0,
    // } };

    return .{ .el = .{
        n, 0, 0,     0,
        0, n, 0,     0,
        0, 0, n + f, -n * f,
        0, 0, 1,     0,
    } };
}

pub fn perspective(comptime T: type, near: Vector(T, 3), far: Vector(T, 3)) Matrix(T, 4, 4) {
    return mulmm(ortho(T, near, far), z_scale(T, near.z(), far.z()));
}

test "projections" {
    const vec3d = wgm.vec3d;
    const vec4d = wgm.vec4d;
    const from_homogenous = wgm.from_homogenous;

    const nudge = struct {
        const NudgeType = enum {
            ninf,
            inf,
        };

        fn aufruf(comptime T: type, comptime typ: NudgeType, comptime n: usize) fn (_: T) T {
            return struct {
                fn aufruf(v: T) T {
                    var ret = v;
                    const inf = std.math.inf(T);

                    inline for (0..n) |_| {
                        ret = std.math.nextAfter(T, ret, if (typ == .inf) inf else -inf);
                    }

                    return ret;
                }
            }.aufruf;
        }
    }.aufruf;

    const nudge1id = nudge(f64, .inf, 1);
    const nudge2id = nudge(f64, .inf, 2);

    const mat_o = ortho(f64, vec3d(2, 3, 4), vec3d(5, 5, 5));
    try std.testing.expectEqual(Matrix(f64, 4, 4){ .el = .{
        2.0 / 3.0, 0,         0,         nudge1id(-7.0 / 3.0),
        0,         2.0 / 2.0, 0,         -8.0 / 2.0,
        0,         0,         1.0 / 1.0, -4.0 / 1.0,
        0,         0,         0,         1,
    } }, mat_o);

    try std.testing.expectEqual(vec4d(nudge2id(-1), -1, 0, 1), mulmm(mat_o, vec4d(2, 3, 4, 1)));
    try std.testing.expectEqual(vec4d(0, 0, 0.5, 1), mulmm(mat_o, vec4d(3.5, 4, 4.5, 1)));

    const mat_p = perspective(f64, vec3d(2, 3, 4), vec3d(5, 5, 5));

    try std.testing.expectEqual(
        vec3d(nudge2id(-1), -1, 0),
        from_homogenous(f64, mulmm(mat_p, vec4d(2, 3, 4, 1))),
    );

    // try std.testing.expectEqual(
    //     vec3d(0, 0, 0.5),
    //     from_homogenous(f64, mulmm(mat_p, vec4d(3.5, 4, 4.5, 1))),
    // );
}

pub fn perspective_fov(comptime T: type, near: T, far: T, fovy: T, aspect: T) Matrix(T, 4, 4) {
    const angle = fovy / 2;
    const ymax = near * @tan(angle);
    const xmax = ymax * aspect;

    const near_vec = Vector(T, 3){ .el = .{
        -xmax,
        -ymax,
        near,
    } };

    const far_vec = Vector(T, 3){ .el = .{
        xmax,
        ymax,
        far,
    } };

    return perspective(T, near_vec, far_vec);
}

pub fn look_at(comptime T: type, eye: Vector(T, 3), at: Vector(T, 3), up: Vector(T, 3)) Matrix(T, 4, 4) {
    const z_hat = wgm.normalized(wgm.sub(at, eye));
    const x_hat = wgm.normalized(wgm.cross(up, z_hat));
    const y_hat = wgm.cross(z_hat, x_hat);

    const x_dot = wgm.dot(x_hat, eye);
    const y_dot = wgm.dot(y_hat, eye);
    const z_dot = wgm.dot(z_hat, eye);

    return Matrix(T, 4, 4){ .el = .{
        x_hat.x(), y_hat.x(), z_hat.x(), 0,
        x_hat.y(), y_hat.y(), z_hat.y(), 0,
        x_hat.z(), y_hat.z(), z_hat.z(), 0,
        -x_dot,    -y_dot,    -z_dot,    1,
    } };
}
