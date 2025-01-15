const Matrix = @import("root.zig").Matrix;
const Vector = @import("root.zig").Vector;
const Traits = @import("root.zig").Traits;

fn ewop(lhs: anytype, rhs: @TypeOf(lhs), comptime fun: fn (lhs: @TypeOf(lhs).ValueType, rhs: @TypeOf(lhs).ValueType) @TypeOf(lhs).ValueType) Traits(@TypeOf(lhs)).EquivMat {
    const MatTraits = Traits(@TypeOf(lhs));
    var ret: MatTraits.EquivMat = undefined;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, fun(lhs.get(row, col), rhs.get(row, col)));
    };

    return ret;
}

pub fn add(lhs: anytype, rhs: @TypeOf(lhs)) Traits(@TypeOf(lhs)).EquivMat {
    const T = @TypeOf(lhs).ValueType;
    return ewop(lhs, rhs, struct {
        fn aufruf(lhs_v: T, rhs_v: T) T {
            return lhs_v + rhs_v;
        }
    }.aufruf);
}

pub fn sub(lhs: anytype, rhs: @TypeOf(lhs)) Traits(@TypeOf(lhs)).EquivMat {
    const T = @TypeOf(lhs).ValueType;
    return ewop(lhs, rhs, struct {
        fn aufruf(lhs_v: T, rhs_v: T) T {
            return lhs_v - rhs_v;
        }
    }.aufruf);
}

pub fn divew(lhs: anytype, rhs: @TypeOf(lhs)) Traits(@TypeOf(lhs)).EquivMat {
    const T = @TypeOf(lhs).ValueType;
    return ewop(lhs, rhs, struct {
        fn aufruf(lhs_v: T, rhs_v: T) T {
            return lhs_v / rhs_v;
        }
    }.aufruf);
}

pub fn divms(lhs: anytype, rhs: @TypeOf(lhs).ValueType) Traits(@TypeOf(lhs)).EquivMat {
    const MatTraits = Traits(@TypeOf(lhs));
    var ret: MatTraits.EquivMat = undefined;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, lhs.get(row, col) / rhs);
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

pub fn mulms(lhs: anytype, rhs: @TypeOf(lhs).ValueType) Traits(@TypeOf(lhs)).EquivMat {
    const MatTraits = Traits(@TypeOf(lhs));
    var ret: MatTraits.EquivMat = undefined;

    for (0..MatTraits.rows) |row| for (0..MatTraits.cols) |col| {
        ret.set(row, col, lhs.get(row, col) * rhs);
    };

    return ret;
}
