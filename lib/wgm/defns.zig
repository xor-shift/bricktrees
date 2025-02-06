const std = @import("std");

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
        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = value;
            _ = fmt;
            _ = options;
            _ = writer;
        }

        const Self = @This();

        pub const ValueType = T;
        pub const rows = Rows;
        pub const cols = Cols;
        pub const lazy: bool = false;

        el: [Rows * Cols]T,

        pub fn get(self: Self, row: usize, col: usize) T {
            std.debug.assert(row < rows);
            std.debug.assert(col < cols);

            return self.el[row * Cols + col];
        }

        pub fn set(self: *Self, row: usize, col: usize, val: T) void {
            std.debug.assert(row < rows);
            std.debug.assert(col < cols);

            self.el[row * Cols + col] = val;
        }

        // zig fmt: off
        pub fn width(self: Self) T { return self.el[0]; }
        pub fn height(self: Self) T { return self.el[1]; }
        pub fn depth(self: Self) T { return self.el[2]; }
        pub fn x(self: Self) T { return self.el[0]; }
        pub fn y(self: Self) T { return self.el[1]; }
        pub fn z(self: Self) T { return self.el[2]; }
        pub fn w(self: Self) T { return self.el[3]; }
        pub fn r(self: Self) T { return self.el[0]; }
        pub fn g(self: Self) T { return self.el[1]; }
        pub fn b(self: Self) T { return self.el[2]; }
        pub fn a(self: Self) T { return self.el[3]; }
        // zig fmt: on

        pub fn lossy_cast(self: Self, comptime U: type) Matrix(U, Rows, Cols) {
            var ret: Matrix(U, Rows, Cols) = undefined;

            for (0..Rows) |row| {
                for (0..Cols) |col| {
                    ret.set(row, col, std.math.lossyCast(U, self.get(row, col)));
                }
            }

            return ret;
        }

        pub fn cast(self: Self, comptime U: type) ?Matrix(U, Rows, Cols) {
            var ret: Matrix(U, Rows, Cols) = undefined;

            for (0..Rows) |row| {
                for (0..Cols) |col| {
                    ret.set(row, col, std.math.cast(U, self.get(row, col)) orelse return null);
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
