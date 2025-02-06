const std = @import("std");
const builtin = std.builtin;

pub fn reduce(vec: anytype, op: builtin.ReduceOp) @TypeOf(vec).ValueType {
    const Vec = @TypeOf(vec);
    const T = Vec.ValueType;

    if (Vec.cols != 1) {
        @compileError("only vectors can be reduced");
    }

    const is_int = @typeInfo(T) == .Int;
    const is_float = @typeInfo(T) == .Float;

    if (!is_int and !is_float) {
        @compileError("only vectors with a ValueType that is either a float or an integer can be reduced");
    }

    const identity: T = switch (op) {
        .And => if (is_int) std.math.maxInt(T) else @compileError("a reduction with .And can only be done on vectors with a ValueType that is an integer"),
        .Or => if (is_int) 0 else @compileError("a reduction with .Or can only be done on vectors with a ValueType that is an integer"),
        .Xor => if (is_int) 0 else @compileError("a reduction with .Xor can only be done on vectors with a ValueType that is an integer"),
        .Min => if (is_int) std.math.maxInt(T) else std.math.inf(T),
        .Max => if (is_int) std.math.minInt(T) else -std.math.inf(T),
        .Add => 0,
        .Mul => 1,
    };

    var ret: T = identity;
    for (0..Vec.rows) |i| ret = switch (op) {
        .And => ret & vec.get(i, 0),
        .Or => ret | vec.get(i, 0),
        .Xor => ret ^ vec.get(i, 0),
        .Min => @min(ret, vec.get(i, 0)),
        .Max => @max(ret, vec.get(i, 0)),
        .Add => ret + vec.get(i, 0),
        .Mul => ret * vec.get(i, 0),
    };

    return ret;
}

pub fn boolean_reduce(mat: anytype, comptime table: [4]bool, comptime initial: bool) bool {
    const Mat = @TypeOf(mat);
    if (Mat.ValueType != bool) {
        @compileError("boolean reduction function called on a non-boolean vector/matrix");
    }

    var ret = initial;
    for (0..Mat.rows) |row| for (0..Mat.cols) |col| {
        const idx = @as(u2, @intFromBool(ret)) << 1 | @as(u2, @intFromBool(mat.get(row, col)));
        ret = table[idx];
    };

    return ret;
}

pub fn all(mat: anytype) bool {
    return boolean_reduce(mat, .{ false, false, false, true }, true);
}

pub fn any(mat: anytype) bool {
    return boolean_reduce(mat, .{ false, true, true, true }, false);
}

pub fn none(mat: anytype) bool {
    return boolean_reduce(mat, .{ true, false, false, false }, true);
}

test "reduction" {
    const vec3z = @import("convenience.zig").vec3z;
    const vec3b = @import("convenience.zig").vec3b;
    const splat3b = @import("convenience.zig").splat3b;

    const vec = vec3z(1, 2, 3);

    try std.testing.expectEqual(6, reduce(vec, .Add));
    try std.testing.expectEqual(6, reduce(vec, .Mul));
    try std.testing.expectEqual(3, reduce(vec, .Or));

    try std.testing.expect(all(splat3b(true)));
    try std.testing.expect(!all(splat3b(false)));
    try std.testing.expect(!all(vec3b(true, false, false)));
}
