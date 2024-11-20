const Matrix = @import("blas.zig").Matrix;
const Vector = @import("blas.zig").Vector;

// zig fmt: off
pub const Mat2f = Matrix(f32, 2, 2);
pub const Mat3f = Matrix(f32, 3, 3);
pub const Mat4f = Matrix(f32, 4, 4);
pub const Vec2f = Vector(f32, 2);
pub const Vec3f = Vector(f32, 3);
pub const Vec4f = Vector(f32, 4);
pub const Mat2d = Matrix(f64, 2, 2);
pub const Mat3d = Matrix(f64, 3, 3);
pub const Mat4d = Matrix(f64, 4, 4);
pub const Vec2d = Vector(f64, 2);
pub const Vec3d = Vector(f64, 3);
pub const Vec4d = Vector(f64, 4);

pub fn vec2f(x: f32, y: f32) Vec2f { return .{ .el = .{x, y} }; }
pub fn vec3f(x: f32, y: f32, z: f32) Vec3f { return .{ .el = .{x, y, z} }; }
pub fn vec4f(x: f32, y: f32, z: f32, w: f32) Vec4f { return .{ .el = .{x, y, z, w} }; }
pub fn vec2d(x: f64, y: f64) Vec2d { return .{ .el = .{x, y} }; }
pub fn vec3d(x: f64, y: f64, z: f64) Vec3d { return .{ .el = .{x, y, z} }; }
pub fn vec4d(x: f64, y: f64, z: f64, w: f64) Vec4d { return .{ .el = .{x, y, z, w} }; }
// zig fmt: on
