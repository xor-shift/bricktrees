const std = @import("std");
const builtin = std.builtin;

const convenience = @import("convenience.zig");
const defns = @import("defns.zig");
const invert = @import("invert.zig");
const map = @import("map.zig");
const ops = @import("ops.zig");
const opt = @import("opt.zig");
const reduction = @import("reduce.zig");
const special = @import("special_mat.zig");

pub usingnamespace convenience;
pub usingnamespace invert;
pub usingnamespace map;
pub usingnamespace ops;
pub usingnamespace reduction;
pub usingnamespace special;

pub const Traits = defns.Traits;

pub const Vector = defns.Vector;
pub const Matrix = defns.Matrix;

test {
    std.testing.refAllDecls(convenience);
    std.testing.refAllDecls(defns);
    std.testing.refAllDecls(invert);
    std.testing.refAllDecls(map);
    std.testing.refAllDecls(ops);
    std.testing.refAllDecls(opt);
    std.testing.refAllDecls(reduction);
    std.testing.refAllDecls(special);
}

pub fn mulmm(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Resize(@TypeOf(lhs).rows, @TypeOf(rhs).cols) {
    const Lhs = @TypeOf(lhs);
    const Rhs = @TypeOf(rhs);

    if (Lhs.ValueType != Rhs.ValueType) @compileError(std.fmt.comptimePrint("incompatible matrix value-types: {any}, {any}", .{ Lhs.ValueType, Rhs.ValueType }));
    if (Lhs.cols != Rhs.rows) @compileError(std.fmt.comptimePrint("lhs.cols ({d}) must equal rhs.rows ({d})", .{ Lhs.cols, Rhs.rows }));

    var ret: Traits(@TypeOf(lhs)).Resize(@TypeOf(lhs).rows, @TypeOf(rhs).cols) = undefined;

    for (0..Lhs.rows) |out_row| {
        for (0..Rhs.cols) |out_col| {
            var sum: Lhs.ValueType = 0;
            for (0..Lhs.cols) |i| {
                sum += lhs.get(out_row, i) * rhs.get(i, out_col);
            }
            ret.set(out_row, out_col, sum);
        }
    }

    return ret;
}

test "matrix multiplication" {
    const lhs: Matrix(u32, 2, 3) = .{ .el = .{
        1, 2, 3,
        4, 5, 6,
    } };

    const rhs: Matrix(u32, 3, 2) = .{ .el = .{
        1, 2,
        3, 4,
        5, 6,
    } };

    const res: Matrix(u32, 2, 2) = mulmm(lhs, rhs);
    const expected: Matrix(u32, 2, 2) = .{ .el = .{
        22, 28,
        49, 64,
    } };
    try std.testing.expectEqual(expected, res);
}

pub fn det(mat: anytype) @TypeOf(mat).ValueType {
    const Mat = @TypeOf(mat);
    const Rows = Mat.rows;
    const Cols = Mat.cols;

    if (Rows != Cols) @compileError(std.fmt.comptimePrint("determinants are only supported for square matrices (tried to get the determinant of a {d}x{d} one)", .{ Rows, Cols }));

    return switch (Rows) {
        1 => mat.get(0, 0),
        2 => mat.get(0, 0) * mat.get(1, 1) - mat.get(0, 1) * mat.get(1, 0),
        3 => val: {
            // zig fmt: off
            const a = mat.get(0, 0); const b = mat.get(0, 1); const c = mat.get(0, 2);
            const d = mat.get(1, 0); const e = mat.get(1, 1); const f = mat.get(1, 2);
            const g = mat.get(2, 0); const h = mat.get(2, 1); const i = mat.get(2, 2);
            // zig fmt: on

            break :val a * e * i + b * f * g + c * d * h - c * e * g - b * d * i - a * f * h;
        },

        else => @compileError("NYI"),
    };
}

test det {
    try std.testing.expectEqual(-2, det(Matrix(isize, 2, 2){ .el = .{ 1, 2, 3, 4 } }));

    try std.testing.expectEqual(0, det(Matrix(isize, 3, 3){ .el = .{
        1, 2, 3,
        4, 5, 6,
        7, 8, 9,
    } }));

    try std.testing.expectEqual(-2, det(Matrix(isize, 3, 3){ .el = .{
        1,  1,  2,
        3,  5,  8,
        13, 21, 33,
    } }));
}

pub fn length(mat: anytype) @TypeOf(mat).ValueType {
    const MatTraits = Traits(@TypeOf(mat));
    var ret: @TypeOf(mat).ValueType = 0;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        const v = mat.get(row, col);
        ret += v * v;
    };

    return @sqrt(ret);
}

pub fn normalized(mat: anytype) Traits(@TypeOf(mat)).EquivMat {
    const MatTraits = Traits(@TypeOf(mat));
    var ret: MatTraits.EquivMat = undefined;

    const len = length(mat);

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, mat.get(row, col) / len);
    };

    return ret;
}

pub fn from_homogenous(comptime T: type, v: Vector(T, 4)) Vector(T, 3) {
    return ops.divew(Vector(T, 3){ .el = .{ v.x(), v.y(), v.z() } }, v.w());
}

pub fn dot(lhs: anytype, rhs: @TypeOf(lhs)) @TypeOf(lhs).ValueType {
    const Vec = @TypeOf(lhs);
    const VecTraits = Traits(Vec);

    if (VecTraits.cols != 1) @compileError("the dot product is for vectors");

    var ret: VecTraits.ValueType = 0;
    for (0..VecTraits.rows) |i| {
        ret += lhs.get(i, 0) * rhs.get(i, 0);
    }

    return ret;
}

pub fn cross(lhs: anytype, rhs: @TypeOf(lhs)) @TypeOf(lhs) {
    const Vec = @TypeOf(lhs);

    if (Vec.rows != 3 or Vec.cols != 1) {
        @compileError("the cross product is only for 3x1 matrices");
    }

    const a1 = lhs.get(0, 0);
    const a2 = lhs.get(1, 0);
    const a3 = lhs.get(2, 0);
    const b1 = rhs.get(0, 0);
    const b2 = rhs.get(1, 0);
    const b3 = rhs.get(2, 0);

    return Vec{.el = .{
        a2 * b3 - a3 * b2,
        a3 * b1 - a1 * b3,
        a1 * b2 - a2 * b1,
    }};
}
