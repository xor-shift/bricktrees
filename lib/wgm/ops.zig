const std = @import("std");

const defns = @import("defns.zig");
const map = @import("map.zig");

const Traits = defns.Traits;

const Vector = defns.Vector;
const Matrix = defns.Matrix;

fn is_mat(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Struct => |v| for (v.decls) |decl| {
            if (std.mem.eql(u8, decl.name, "ValueType")) return true;
        },
        else => {},
    }

    return false;
}

pub fn ArithResult(comptime Lhs: type, comptime Rhs: type) type {
    if (!is_mat(Rhs)) {
        return ArithResult(Lhs, Traits(Lhs).Rebind(Rhs));
    }

    const TL = Traits(Lhs);
    const TR = Traits(Rhs);

    std.debug.assert(TL.rows == TR.rows and TL.cols == TR.cols);

    const Res = @TypeOf(std.mem.zeroes(Traits(Lhs).ValueType) + std.mem.zeroes(Traits(Rhs).ValueType));

    return Traits(Lhs).Rebind(Res);
}

fn impl(lhs: anytype, rhs: anytype, comptime fun: []const u8) ArithResult(@TypeOf(lhs), @TypeOf(rhs)) {
    const Rhs = @TypeOf(rhs);

    if (comptime is_mat(Rhs)) {
        return map.binary_map(lhs, rhs, @field(map.binary_ops, fun), .{});
    } else {
        return map.unary_map(lhs, @field(map.unary_ops, fun), .{rhs});
    }
}

pub fn add(lhs: anytype, rhs: anytype) ArithResult(@TypeOf(lhs), @TypeOf(rhs)) {
    return impl(lhs, rhs, "add");
}

pub fn sub(lhs: anytype, rhs: anytype) ArithResult(@TypeOf(lhs), @TypeOf(rhs)) {
    return impl(lhs, rhs, "sub");
}

pub fn mulew(lhs: anytype, rhs: anytype) ArithResult(@TypeOf(lhs), @TypeOf(rhs)) {
    return impl(lhs, rhs, "mul");
}

pub fn divew(lhs: anytype, rhs: anytype) ArithResult(@TypeOf(lhs), @TypeOf(rhs)) {
    return impl(lhs, rhs, "div");
}

test "ops" {
    const vec3z = @import("convenience.zig").vec3z;
    const vec3f = @import("convenience.zig").vec3f;

    try std.testing.expectEqual(vec3z(4, 4, 4), add(vec3z(1, 2, 3), vec3z(3, 2, 1)));
    try std.testing.expectEqual(vec3z(2, 3, 4), add(vec3z(1, 2, 3), 1));
    try std.testing.expectEqual(vec3z(-1, 0, 1), sub(vec3z(1, 2, 3), 2));
    try std.testing.expectEqual(vec3z(2, 4, 6), mulew(vec3z(1, 2, 3), 2));
    try std.testing.expectEqual(vec3z(1, 2, 3), divew(vec3z(2, 4, 6), 2));
    try std.testing.expectEqual(vec3f(2, 3, 4), add(vec3f(1, 2, 3), 1));

    try std.testing.expectEqual(vec3f(0.5, 1.5, 2.5), sub(vec3f(1, 2, 3), 0.5));
    try std.testing.expectEqual(vec3f(0.5, 1.0, 1.5), divew(vec3f(1, 2, 3), 2.0));
}
