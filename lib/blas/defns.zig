const Matrix = @import("root.zig").Matrix;
const Vector = @import("root.zig").Vector;

pub fn explode(comptime T: type, comptime Dims: usize, v: T) Vector(T, Dims) {
    var ret: Vector(T, Dims) = undefined;
    @memset(&ret.el, v);
    return ret;
}

// zig fmt: off
pub const Vec2f = Vector(f32, 2);
pub const Vec3f = Vector(f32, 3);
pub const Vec4f = Vector(f32, 4);
pub const Vec2d = Vector(f64, 2);
pub const Vec3d = Vector(f64, 3);
pub const Vec4d = Vector(f64, 4);

pub const Vec2u = Vector(u32, 2);
pub const Vec3u = Vector(u32, 3);
pub const Vec4u = Vector(u32, 4);
pub const Vec2i = Vector(i32, 2);
pub const Vec3i = Vector(i32, 3);
pub const Vec4i = Vector(i32, 4);

pub const Vec2uz = Vector(usize, 2);
pub const Vec3uz = Vector(usize, 3);
pub const Vec4uz = Vector(usize, 4);
pub const Vec2z = Vector(isize, 2);
pub const Vec3z = Vector(isize, 3);
pub const Vec4z = Vector(isize, 4);

pub const Mat2d = Matrix(f64, 2, 2);
pub const Mat3d = Matrix(f64, 3, 3);
pub const Mat4d = Matrix(f64, 4, 4);
pub const Mat2f = Matrix(f32, 2, 2);
pub const Mat3f = Matrix(f32, 3, 3);
pub const Mat4f = Matrix(f32, 4, 4);

//pub fn vec(comptime T: type, args: anytype) Vector(T, determine_vector_size(@TypeOf(args))) {}

pub fn vec2f(x: f32, y: f32) Vec2f { return .{ .el = .{x, y} }; }
pub fn vec3f(x: f32, y: f32, z: f32) Vec3f { return .{ .el = .{x, y, z} }; }
pub fn vec4f(x: f32, y: f32, z: f32, w: f32) Vec4f { return .{ .el = .{x, y, z, w} }; }
pub fn vec2d(x: f64, y: f64) Vec2d { return .{ .el = .{x, y} }; }
pub fn vec3d(x: f64, y: f64, z: f64) Vec3d { return .{ .el = .{x, y, z} }; }
pub fn vec4d(x: f64, y: f64, z: f64, w: f64) Vec4d { return .{ .el = .{x, y, z, w} }; }

pub fn vec2u(x: u32, y: u32) Vec2u { return .{ .el = .{x, y} }; }
pub fn vec3u(x: u32, y: u32, z: u32) Vec3u { return .{ .el = .{x, y, z} }; }
pub fn vec4u(x: u32, y: u32, z: u32, w: u32) Vec4u { return .{ .el = .{x, y, z, w} }; }
pub fn vec2i(x: i32, y: i32) Vec2i { return .{ .el = .{x, y} }; }
pub fn vec3i(x: i32, y: i32, z: i32) Vec3i { return .{ .el = .{x, y, z} }; }
pub fn vec4i(x: i32, y: i32, z: i32, w: i32) Vec4i { return .{ .el = .{x, y, z, w} }; }

pub fn vec2uz(x: usize, y: usize) Vec2uz { return .{ .el = .{x, y} }; }
pub fn vec3uz(x: usize, y: usize, z: usize) Vec3uz { return .{ .el = .{x, y, z} }; }
pub fn vec4uz(x: usize, y: usize, z: usize, w: usize) Vec4uz { return .{ .el = .{x, y, z, w} }; }
pub fn vec2z(x: isize, y: isize) Vec2z { return .{ .el = .{x, y} }; }
pub fn vec3z(x: isize, y: isize, z: isize) Vec3z { return .{ .el = .{x, y, z} }; }
pub fn vec4z(x: isize, y: isize, z: isize, w: isize) Vec4z { return .{ .el = .{x, y, z, w} }; }

pub fn splat2f(v: f32) Vec2f { return explode(f32, 2, v); }
pub fn splat3f(v: f32) Vec3f { return explode(f32, 3, v); }
pub fn splat4f(v: f32) Vec4f { return explode(f32, 4, v); }
pub fn splat2d(v: f64) Vec2d { return explode(f64, 2, v); }
pub fn splat3d(v: f64) Vec3d { return explode(f64, 3, v); }
pub fn splat4d(v: f64) Vec4d { return explode(f64, 4, v); }

pub fn splat2u(v: u32) Vec2u { return explode(u32, 2, v); }
pub fn splat3u(v: u32) Vec3u { return explode(u32, 3, v); }
pub fn splat4u(v: u32) Vec4u { return explode(u32, 4, v); }
pub fn splat2i(v: i32) Vec2i { return explode(i32, 2, v); }
pub fn splat3i(v: i32) Vec3i { return explode(i32, 3, v); }
pub fn splat4i(v: i32) Vec4i { return explode(i32, 4, v); }

pub fn splat2uz(v: usize) Vec2uz { return explode(usize, 2, v); }
pub fn splat3uz(v: usize) Vec3uz { return explode(usize, 3, v); }
pub fn splat4uz(v: usize) Vec4uz { return explode(usize, 4, v); }
pub fn splat2z(v: isize) Vec2z { return explode(isize, 2, v); }
pub fn splat3z(v: isize) Vec3z { return explode(isize, 3, v); }
pub fn splat4z(v: isize) Vec4z { return explode(isize, 4, v); }
// zig fmt: on

