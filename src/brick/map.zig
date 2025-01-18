const std = @import("std");

const Voxel = @import("defns.zig").Voxel;
const PackedVoxel = @import("defns.zig").PackedVoxel;

pub fn U8Map(comptime depth: usize) type {
    return struct {
        pub const side_length: usize = 1 << (depth + 1);
        pub const no_tree_nodes = (1 << (3 * (depth + 2))) / 7 - 1;

        voxels: [side_length * side_length * side_length]PackedVoxel,
        tree: [no_tree_nodes / 8]u8,
    };
}

test "U8Map constants" {
    try std.testing.expectEqual(2, U8Map(0).side_length);
    try std.testing.expectEqual(4, U8Map(1).side_length);
    try std.testing.expectEqual(8, U8Map(2).side_length);
    try std.testing.expectEqual(16, U8Map(3).side_length);
    try std.testing.expectEqual(8, U8Map(0).no_tree_nodes);
    try std.testing.expectEqual(72, U8Map(1).no_tree_nodes);
    try std.testing.expectEqual(584, U8Map(2).no_tree_nodes);
    try std.testing.expectEqual(4680, U8Map(3).no_tree_nodes);
}

pub fn U64Map(comptime depth: usize) type {
    return struct {
        pub const side_length: usize = 1 << (2 * (depth + 1));
        pub const no_tree_nodes = (1 << (6 * (depth + 2))) / 63 - 1;

        voxels: [side_length * side_length * side_length]PackedVoxel,
        tree: [no_tree_nodes / 64]u64,
    };
}

test "U64Map constants" {
    try std.testing.expectEqual(4, U64Map(0).side_length);
    try std.testing.expectEqual(16, U64Map(1).side_length);
    try std.testing.expectEqual(64, U64Map(2).side_length);
    try std.testing.expectEqual(256, U64Map(3).side_length);
    try std.testing.expectEqual(64, U64Map(0).no_tree_nodes);
    try std.testing.expectEqual(4160, U64Map(1).no_tree_nodes);
    try std.testing.expectEqual(266304, U64Map(2).no_tree_nodes);
    try std.testing.expectEqual(17043520, U64Map(3).no_tree_nodes);
}
