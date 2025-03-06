const std = @import("std");

const dyn = @import("root.zig");

const IShape = struct {
    pub const DynStatic = dyn.IFaceStuff(IShape);

    pub const get_area = fn (dyn.Fat(*const IShape)) f64;

    pub const set_mul = fn (dyn.Fat(*IShape), f64) void;

    pub fn foo(_: dyn.Fat(IShape)) void {}
};

const ILocated = struct {
    pub const DynStatic = dyn.IFaceStuff(ILocated);

    pub fn get_distance(self: dyn.Fat(ILocated), to: [2]f64) f64 {
        _ = self;
        _ = to;

        return 0;
    }

    pub fn get_location(_: dyn.Fat(*const ILocated)) [2]f64 {
        return .{ 0, 0 };
    }

    pub fn set_location(_: dyn.Fat(*ILocated), _: [2]f64) void {}
};

const Rectangle = struct {
    pub const DynStatic = dyn.ConcreteStuff(Rectangle, .{ IShape, ILocated });

    mul: f64,
    width: f64,
    height: f64,

    pub fn get_area(self: Rectangle) f64 {
        return self.width * self.height * self.mul;
    }

    pub fn set_mul(self: *Rectangle, mul: f64) void {
        self.mul = mul;
    }
};

const Sphere = struct {
    pub const DynStatic = dyn.ConcreteStuff(Sphere, .{ IShape, ILocated });

    mul: f64,
    r: f64,

    pub fn get_area(self: *const Sphere) f64 {
        return std.math.pi * self.r * self.r * self.mul;
    }

    pub fn set_mul(self: *Sphere, mul: f64) void {
        self.mul = mul;
    }
};

test {
    var rect: Rectangle = .{
        .mul = 1,
        .width = 3,
        .height = 4,
    };

    var sphere: Sphere = .{
        .mul = 1,
        .r = 6.0 / std.math.sqrt(@as(f64, std.math.pi)),
    };

    const shape_0 = dyn.Fat(*IShape).init(&rect);
    const shape_1 = dyn.Fat(*IShape).init(&sphere);

    try std.testing.expectEqual(12, shape_0.di(0, .{}));
    shape_0.di(1, .{2});
    try std.testing.expectEqual(24, shape_0.di(0, .{}));

    try std.testing.expectEqual(36, shape_1.d("get_area", .{}));
    shape_1.d("set_mul", .{2});
    try std.testing.expectEqual(72, shape_1.d("get_area", .{}));

    // @compileLog(virtual_fns(IShape));
}
