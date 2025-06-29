const std = @import("std");

const qov = @import("qov");

const Voxel = qov.Voxel;
const PackedVoxel = qov.PackedVoxel;

pub fn Brickmap(comptime depth_arg: usize) type {
    return struct {
        pub const depth: u6 = depth_arg;
        pub const side_length: usize = 1 << depth;
        pub const side_length_i: isize = @intCast(side_length);
        pub const volume: usize = 1 << (depth * 3);

        const Self = Brickmap(depth_arg);

        /// The data is row-major so index like voxels[z][y][x]
        voxels: [side_length][side_length][side_length]PackedVoxel,

        pub inline fn flat(self: *Self) *[volume]PackedVoxel {
            return @ptrCast(&self.voxels);
        }

        pub inline fn c_flat(self: *const Self) *const [volume]PackedVoxel {
            return @ptrCast(&self.voxels);
        }

        pub inline fn flat_u32(self: *Self) *[volume]u32 {
            return @ptrCast(self.flat());
        }

        pub inline fn c_flat_u32(self: *const Self) *const [volume]u32 {
            return @ptrCast(self.c_flat());
        }
    };
}
