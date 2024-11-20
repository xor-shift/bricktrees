const std = @import("std");

pub usingnamespace @import("defns.zig");
pub usingnamespace @import("special_mat.zig");

pub fn Traits(comptime Mat: type) type {
    return struct {
        const Self = @This();

        pub const is_vector = Mat.cols == 1;
        pub const is_scalar = Mat.cols == 1 and Mat.rows == 1;

        pub const ValueType = Mat.ValueType;
        pub const rows = Mat.rows;
        pub const cols = Mat.cols;

        pub const lazy: bool = Mat.lazy;
        pub const modifiable: bool = false;

        pub const EquivMat = Matrix(Mat.ValueType, Mat.rows, Mat.cols);

        pub fn Resize(comptime Rows: usize, comptime Cols: usize) type {
            return Matrix(Self.ValueType, Rows, Cols);
        }

        pub fn Rebind(comptime T: type) type {
            return Matrix(T, Self.rows, Self.cols);
        }
    };
}

pub fn Matrix(comptime T: type, comptime Rows: usize, comptime Cols: usize) type {
    return struct {
        const Self = @This();

        pub const ValueType = T;
        pub const rows = Rows;
        pub const cols = Cols;
        pub const lazy: bool = false;

        el: [Rows * Cols]T,

        pub fn get(self: Self, row: usize, col: usize) T {
            return self.el[row * Cols + col];
        }

        pub fn set(self: *Self, row: usize, col: usize, val: T) void {
            self.el[row * Cols + col] = val;
        }

        pub fn lossy_cast(self: Self, comptime U: type) Matrix(U, Rows, Cols) {
            var ret: Matrix(U, Rows, Cols) = undefined;

            for (0..Rows) |row| {
                for (0..Cols) |col| {
                    ret.set(col, row, std.math.lossyCast(U, self.get(row, col)));
                }
            }

            return ret;
        }

        pub fn transposed(self: Self) Matrix(T, Cols, Rows) {
            var ret: Matrix(T, Cols, Rows) = undefined;

            for (0..Rows) |row| {
                for (0..Cols) |col| {
                    ret.set(col, row, self.get(row, col));
                }
            }

            return ret;
        }

        pub fn add(self: *Self, rhs: Self) void {
            for (0..Rows * Cols) |i| self.el[i] += rhs.el[i];
        }
    };
}

pub fn Vector(comptime T: type, comptime Dimension: usize) type {
    return Matrix(T, Dimension, 1);
}

pub fn swizzle(vec: anytype, comptime swizzle_str: []const u8) Traits(@TypeOf(vec)).Resize(swizzle_str.len, 1) {
    return undefined;
}

fn mul_naive(out: anytype, lhs: anytype, rhs: anytype) void {
    const Lhs = @TypeOf(lhs);
    const Rhs = @TypeOf(rhs);

    for (0..Lhs.rows) |out_row| {
        for (0..Rhs.cols) |out_col| {
            var sum: Lhs.ValueType = 0;
            for (0..Lhs.cols) |i| {
                sum += lhs.get(out_row, i) * rhs.get(i, out_col);
            }
            out.set(out_row, out_col, sum);
        }
    }
}

pub fn mulmm(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Resize(@TypeOf(lhs).rows, @TypeOf(rhs).cols) {
    const Lhs = @TypeOf(lhs);
    const Rhs = @TypeOf(rhs);

    if (Lhs.ValueType != Rhs.ValueType) @compileError(std.fmt.comptimePrint("incompatible matrix value-types: {any}, {any}", .{ Lhs.ValueType, Rhs.ValueType }));
    if (Lhs.cols != Rhs.rows) @compileError(std.fmt.comptimePrint("lhs.cols ({d}) must equal rhs.rows ({d})", .{ Lhs.cols, Rhs.rows }));

    var ret: Traits(@TypeOf(lhs)).Resize(@TypeOf(lhs).rows, @TypeOf(rhs).cols) = undefined;

    const characteristic_arr: [4]usize = .{ Lhs.rows, Lhs.cols, Rhs.rows, Rhs.cols };
    const characteristic: u256 = @bitCast(characteristic_arr);

    switch (characteristic) {
        @as(u256, @bitCast([4]usize{ 2, 2, 2, 2 })) => @import("opt.zig").mul_strassen_2x2_2x2(&ret, lhs, rhs),
        else => mul_naive(&ret, lhs, rhs),
    }

    return ret;
}

fn ewop(lhs: anytype, rhs: @TypeOf(lhs), comptime fun: fn (lhs: @TypeOf(lhs).ValueType, rhs: @TypeOf(lhs).ValueType) @TypeOf(lhs).ValueType) Traits(@TypeOf(lhs)).EquivMat {
    const MatTraits = Traits(@TypeOf(lhs));
    var ret: MatTraits.EquivMat = undefined;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, fun(lhs.get(row, col), rhs.get(row, col)));
    };

    return ret;
}

pub fn mulew(lhs: anytype, rhs: @TypeOf(lhs)) Traits(@TypeOf(lhs)).EquivMat {
    const T = @TypeOf(lhs).ValueType;
    return ewop(lhs, rhs, struct {
        fn aufruf(lhs_v: T, rhs_v: T) T {
            return lhs_v * rhs_v;
        }
    }.aufruf);
}

pub fn add(lhs: anytype, rhs: @TypeOf(lhs)) Traits(@TypeOf(lhs)).EquivMat {
    const T = @TypeOf(lhs).ValueType;
    return ewop(lhs, rhs, struct {
        fn aufruf(lhs_v: T, rhs_v: T) T {
            return lhs_v + rhs_v;
        }
    }.aufruf);
}

pub fn mulms(lhs: anytype, rhs: @TypeOf(lhs).ValueType) Traits(@TypeOf(lhs)).EquivMat {
    const MatTraits = Traits(@TypeOf(lhs));
    var ret: MatTraits.EquivMat = undefined;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, lhs.get(row, col) * rhs);
    };

    return ret;
}

test "matrix multiplication" {
    const lhs: Matrix(u32, 2, 3) = .{ .el = .{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 },
    } };

    const rhs: Matrix(u32, 3, 2) = .{ .el = .{
        .{ 1, 2 },
        .{ 3, 4 },
        .{ 5, 6 },
    } };

    const res: Matrix(u32, 2, 2) = mulmm(lhs, rhs);
    const expected: Matrix(u32, 2, 2) = .{ .el = .{
        .{ 22, 28 },
        .{ 49, 64 },
    } };
    try std.testing.expectEqual(expected, res);
}

pub fn det(mat: anytype) @TypeOf(mat).ValueType {
    const Mat = @TypeOf(mat);
    const Rows = Mat.rows;
    const Cols = Mat.cols;

    if (Rows != Cols) @compileError(std.fmt.comptimePrint("determinants are only supported for square matrices (tried to get the determinant of a {d}x{d} one)", .{ Rows, Cols }));

    return switch (Rows) {
        1 => @compileError("can't take the determinant of a 1x1 matrix"),
        2 => mat.get(0, 0) * mat.get(0, 3) - mat.get(0, 1) * mat.get(0, 2),
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
