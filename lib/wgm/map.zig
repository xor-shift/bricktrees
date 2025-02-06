const std = @import("std");

const defns = @import("defns.zig");
const conv = @import("convenience.zig");

const Traits = defns.Traits;

const Vector = defns.Vector;
const Matrix = defns.Matrix;

fn UnaryMapReturnType(comptime Mat: type, comptime fun: anytype, comptime Args: type) type {
    return @TypeOf(@call(
        .auto,
        fun,
        std.mem.zeroes(Args) ++ .{
            @as(usize, 0),
            @as(usize, 0),
            std.mem.zeroes(Traits(Mat).ValueType),
        },
    ));
}

/// https://github.com/ziglang/zig/issues/2935
/// `Args` must be zero-initializable.
pub fn UnaryMappedType(comptime Mat: type, comptime fun: anytype, comptime Args: type) type {
    return Traits(Mat).Rebind(UnaryMapReturnType(Mat, fun, Args));
}

pub fn MaybeUnaryMappedType(comptime Mat: type, comptime fun: anytype, comptime Args: type) type {
    const T = UnaryMapReturnType(Mat, fun, Args);
    return ?Traits(Mat).Rebind(@typeInfo(T).Optional.child);
}

/// Calls `fun` on every element of `mat`.
/// The first arguments to `fun` are determined by `initial_args` and the rest
/// are the row, the column, and the value at said location.
pub fn unary_map(mat: anytype, comptime fun: anytype, initial_args: anytype) UnaryMappedType(@TypeOf(mat), fun, @TypeOf(initial_args)) {
    const Mat = @TypeOf(mat);
    var ret: UnaryMappedType(Mat, fun, @TypeOf(initial_args)) = undefined;

    for (0..Mat.rows) |row| for (0..Mat.cols) |col| {
        const res = @call(.auto, fun, initial_args ++ .{ row, col, mat.get(row, col) });
        ret.set(row, col, res);
    };

    return ret;
}

pub const unary_ops = struct {
    pub fn identity(_: usize, _: usize, v: anytype) @TypeOf(v) {
        return v;
    }

    pub fn negate(_: usize, _: usize, v: anytype) @TypeOf(-v) {
        return -v;
    }

    pub fn add(by: anytype, _: usize, _: usize, v: anytype) @TypeOf(by + v) {
        return v + by;
    }

    pub fn sub(by: anytype, _: usize, _: usize, v: anytype) @TypeOf(by - v) {
        return v - by;
    }

    pub fn mul(by: anytype, _: usize, _: usize, v: anytype) @TypeOf(by * v) {
        return v * by;
    }

    pub fn div(by: anytype, _: usize, _: usize, v: anytype) @TypeOf(@divTrunc(by, v)) {
        if (@typeInfo(@TypeOf(v)) == .Int) {
            return @divTrunc(v, by);
        } else {
            return v / by;
        }
    }
};

test unary_map {
    const vec = conv.vec3uz(1, 2, 3);

    const after_identity = unary_map(vec, unary_ops.identity, .{});
    try std.testing.expectEqual(vec, after_identity);

    const mul_3 = unary_map(vec, unary_ops.mul, .{3});
    try std.testing.expectEqual(conv.vec3uz(3, 6, 9), mul_3);
}

/// See `map`.
///
/// If `fun` returns a `null`, a null is returned.
pub fn maybe_unary_map(mat: anytype, comptime fun: anytype, initial_args: anytype) MaybeUnaryMappedType(@TypeOf(mat), fun, @TypeOf(initial_args)) {
    const Mat = @TypeOf(mat);
    const Maybe = MaybeUnaryMappedType(Mat, fun, @TypeOf(initial_args));
    const Concrete = @typeInfo(Maybe).Optional.child;
    var ret: Concrete = undefined;

    for (0..Mat.rows) |row| {
        for (0..Mat.cols) |col| {
            const res = @call(.auto, fun, initial_args ++ .{ row, col, mat.get(row, col) }) orelse return null;
            ret.set(row, col, res);
        }
    }

    return ret;
}

/// Turns a `Matrix(?T, r, c)` into a `?Matrix(T, r, c)`.
/// I'm sure functional programming people have a word that describes this op.
pub fn invert_optional(mat: anytype) ?Traits(@TypeOf(mat)).Rebind(@typeInfo(Traits(@TypeOf(mat)).ValueType).Optional.child) {
    return maybe_unary_map(mat, unary_ops.identity, .{});
}

test maybe_unary_map {
    try std.testing.expectEqual(
        Vector(usize, 3){ .el = .{ 1, 2, 3 } },
        invert_optional(Vector(?usize, 3){ .el = .{ 1, 2, 3 } }),
    );

    try std.testing.expectEqual(
        null,
        invert_optional(Vector(?usize, 3){ .el = .{ null, 2, 3 } }),
    );
}

pub fn BinaryMapReturnType(comptime Lhs: type, comptime Rhs: type, comptime fun: anytype, comptime Args: type) type {
    return @TypeOf(@call(
        .auto,
        fun,
        std.mem.zeroes(Args) ++ .{
            @as(usize, 0),
            @as(usize, 0),
            std.mem.zeroes(Traits(Lhs).ValueType),
            std.mem.zeroes(Traits(Rhs).ValueType),
        },
    ));
}

pub fn BinaryMappedType(comptime Lhs: type, comptime Rhs: type, comptime fun: anytype, comptime Args: type) type {
    return Traits(Lhs).Rebind(BinaryMapReturnType(Lhs, Rhs, fun, Args));
}

pub fn MaybeBinaryMapType() type {
    return noreturn;
}

pub fn binary_map(lhs: anytype, rhs: anytype, comptime fun: anytype, initial_args: anytype) BinaryMappedType(@TypeOf(lhs), @TypeOf(rhs), fun, @TypeOf(initial_args)) {
    const Lhs = @TypeOf(lhs);
    const Rhs = @TypeOf(rhs);
    var ret: BinaryMappedType(Lhs, Rhs, fun, @TypeOf(initial_args)) = undefined;

    for (0..Lhs.rows) |row| for (0..Lhs.cols) |col| {
        const res = @call(.auto, fun, initial_args ++ .{
            row,
            col,
            lhs.get(row, col),
            rhs.get(row, col),
        });
        ret.set(row, col, res);
    };

    return ret;
}

pub const binary_ops = struct {
    pub fn add(_: usize, _: usize, lhs: anytype, rhs: anytype) @TypeOf(lhs + rhs) {
        return lhs + rhs;
    }

    pub fn sub(_: usize, _: usize, lhs: anytype, rhs: anytype) @TypeOf(lhs - rhs) {
        return lhs - rhs;
    }

    pub fn mul(_: usize, _: usize, lhs: anytype, rhs: anytype) @TypeOf(lhs * rhs) {
        return lhs * rhs;
    }

    pub fn div(_: usize, _: usize, lhs: anytype, rhs: anytype) @TypeOf(@divTrunc(lhs, rhs)) {
        if (@typeInfo(@TypeOf(lhs)) == .Int) {
            return @divTrunc(lhs, rhs);
        } else {
            return lhs / rhs;
        }
    }
};

test binary_map {
    // checking if @TypeOf(lhs * rhs) requires things to be known at comptime
    _ = binary_map(conv.splat3z(std.time.timestamp()), conv.splat3z(1), binary_ops.mul, .{});

    try std.testing.expectEqual(
        conv.vec3z(3, 6, 11),
        binary_map(conv.vec3z(1, 2, 3), conv.vec3z(2, 4, 8), binary_ops.add, .{}),
    );

    try std.testing.expectEqual(
        conv.vec3z(-1, -2, 11),
        binary_map(conv.vec3z(1, 2, 3), conv.vec3z(2, 4, -8), binary_ops.sub, .{}),
    );

    try std.testing.expectEqual(
        conv.vec3z(2, 8, 24),
        binary_map(conv.vec3z(1, 2, 3), conv.vec3z(2, 4, 8), binary_ops.mul, .{}),
    );

    try std.testing.expectEqual(
        conv.vec3z(2, 2, 2),
        binary_map(conv.vec3z(2, 4, 8), conv.vec3z(1, 2, 3), binary_ops.div, .{}),
    );
}

const Compare = enum {
    lt,
    lte,
    gt,
    gte,
    eq,
    neq,
};

fn relational_map(lhs: anytype, rhs: anytype, compare: Compare) Traits(@TypeOf(lhs)).Rebind(bool) {
    const Mat = @TypeOf(lhs);
    const Rebound = Traits(Mat).Rebind(bool);

    var ret: Rebound = undefined;

    for (0..Mat.rows) |row| for (0..Mat.cols) |col| {
        const lhs_val = lhs.get(row, col);
        const rhs_val = rhs.get(row, col);
        const res = switch (compare) {
            .lt => lhs_val < rhs_val,
            .lte => lhs_val <= rhs_val,
            .gt => lhs_val > rhs_val,
            .gte => lhs_val >= rhs_val,
            .eq => lhs_val == rhs_val,
            .neq => lhs_val != rhs_val,
        };
        ret.set(row, col, res);
    };

    return ret;
}

pub fn greater_than(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .gt);
}

pub fn greater_than_equal(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .gte);
}

pub fn less_than(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .lt);
}

pub fn less_than_equal(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .lte);
}

pub fn equal(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .eq);
}

pub fn not_equal(lhs: anytype, rhs: anytype) Traits(@TypeOf(lhs)).Rebind(bool) {
    return relational_map(lhs, rhs, .neq);
}

test "ordering" {
    const vec4b = @import("convenience.zig").vec4b;
    const vec4z = @import("convenience.zig").vec4z;
    const splat4z = @import("convenience.zig").splat4z;

    try std.testing.expectEqual(
        vec4b(true, true, false, false),
        less_than(vec4z(-100, 0, 2, 3), splat4z(2)),
    );
}

pub fn negate(mat: anytype) @TypeOf(mat) {
    return unary_map(mat, unary_ops.negate, .{});
}
