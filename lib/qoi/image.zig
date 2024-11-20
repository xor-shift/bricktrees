const std = @import("std");
const color = @import("color.zig");

const Image = @This();

alloc: std.mem.Allocator,

width: usize,
height: usize,
depth: usize,

color_space: color.ColorSpace,

data: [][4]u8,

pub fn init(width: usize, height: usize, depth: usize, color_space: color.ColorSpace, alloc: std.mem.Allocator) std.mem.Allocator.Error!@This() {
    return .{
        .alloc = alloc,

        .width = width,
        .height = height,
        .depth = depth,

        .color_space = color_space,

        .data = try alloc.alloc([4]u8, width * height * depth),
    };
}

pub fn deinit(self: Image) void {
    self.alloc.free(self.data);
}
