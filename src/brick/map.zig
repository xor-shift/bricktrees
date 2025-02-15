const std = @import("std");

const bit_utils = @import("../bit_utils.zig");

const defns = @import("defns.zig");

const Voxel = defns.Voxel;
const PackedVoxel = defns.PackedVoxel;

const power_sum = bit_utils.power_sum;
const stuff_zeroes = bit_utils.stuff_zeroes;
const funny_merge_64 = bit_utils.funny_merge_64;

pub fn MkTraits(comptime NodeTypeArg: type, comptime depth_arg: u6) type {
    std.debug.assert(NodeTypeArg == u8 or NodeTypeArg == u64);
    std.debug.assert(depth_arg != 0);

    // 3 or 6
    const node_size_log_2 = @ctz(@as(usize, @bitSizeOf(NodeTypeArg)));

    const bits_per_axis_per_level = node_size_log_2 / 3;

    return struct {
        pub const VoxelType = PackedVoxel;
        pub const NodeType = NodeTypeArg;

        pub const depth: u6 = depth_arg;
        pub const side_length: usize = 1 << (bits_per_axis_per_level * depth);
        pub const side_length_i: isize = @intCast(side_length);
        pub const volume: usize = 1 << (3 * bits_per_axis_per_level * depth);

        pub const no_tree_bits: usize = power_sum(usize, depth, node_size_log_2);

        /// Returns 8^0 + 8^1 + ... + 8^n.
        fn bits_before_level(level: u6) usize {
            return power_sum(usize, @intCast(level), node_size_log_2);
        }

        /// For the sake of verbosity.
        /// Returns 8^n aka the number of bits at a given tree level, simple as.
        fn bits_at_level(level: u6) usize {
            return @as(usize, 1) << @as(u6, @intCast(node_size_log_2 * level));
        }
    };
}

fn generate_tree_scalar_u8(
    comptime Traits: type,
    comptime level: u6,
    out: *[Traits.bits_at_level(level) / 8]u8,
    in: if (level == Traits.depth - 1)
        *const [Traits.volume]PackedVoxel
    else
        *const [Traits.bits_at_level(level + 1) / 8]u8,
) void {
    const last_level = level == Traits.depth - 1;

    const group_table: [8]usize = comptime .{
        stuff_zeroes(.left, usize, 0b000, 3, 1, level),
        stuff_zeroes(.left, usize, 0b001, 3, 1, level),
        stuff_zeroes(.left, usize, 0b010, 3, 1, level),
        stuff_zeroes(.left, usize, 0b011, 3, 1, level),
        stuff_zeroes(.left, usize, 0b100, 3, 1, level),
        stuff_zeroes(.left, usize, 0b101, 3, 1, level),
        stuff_zeroes(.left, usize, 0b110, 3, 1, level),
        stuff_zeroes(.left, usize, 0b111, 3, 1, level),
    };

    for (0..Traits.bits_at_level(level)) |outer| {
        const expanded_idx = stuff_zeroes(.right, usize, outer, 3, level, 1);

        var group_is_occupied: bool = false;

        // gl as in group-local
        for (0..8) |gl_elem_idx| {
            const elem_idx =
                expanded_idx +
                group_table[gl_elem_idx];

            const element_is_occupied = if (last_level)
                @as(u32, @bitCast(in[elem_idx])) != 0
            else blk: {
                const in_group_idx = elem_idx / 8;
                // i have given up with naming
                const in_elem_idx: u3 = @intCast(elem_idx % 8);

                break :blk ((in[in_group_idx] >> in_elem_idx) & 1) != 0;
            };

            group_is_occupied = group_is_occupied or element_is_occupied;
        }

        const out_group_idx = outer / 8;
        const out_elem_idx = outer % 8;

        if (group_is_occupied) {
            out[out_group_idx] |= @as(u8, 1) << @as(u3, @intCast(out_elem_idx));
        }
    }
}

/// `depth` signifies the size of a single component of the coordinates of
/// voxels and as such may not be 0.
///
/// A `depth` of 1 results in an empty tree.
pub fn U8Map(comptime depth: u6) type {
    return struct {
        pub const Self = U8Map(depth);

        pub const Traits = MkTraits(u8, depth);

        pub fn to_index(coord: [3]usize) usize {
            return coord[0] +
                coord[1] * Traits.side_length +
                coord[2] * Traits.side_length * Traits.side_length;
        }

        pub fn tree_at_level(self: *Self, level: u6) []u8 {
            const bbl = Self.Traits.bits_before_level;
            return self.tree[bbl(level) / 8 .. bbl(level + 1) / 8];
        }

        pub fn generate_tree(self: *Self) void {
            @memset(self.tree[0..], 0);

            const foo = @import("./brickmap.zig");
            const bar = @import("./bricktree/u8.zig");

            const as_bm: *foo.Brickmap(depth) = @ptrCast(&self.voxels);

            bar.make_tree_inplace(depth, as_bm, &self.tree);

            // generate_tree_scalar_u8(
            //     Self.Traits,
            //     depth - 1,
            //     @ptrCast(self.tree_at_level(depth - 1)),
            //     self.voxels[0..],
            // );

            // inline for (1..depth - 1) |i| {
            //     const level = depth - i - 1;
            //     generate_tree_scalar_u8(
            //         Self.Traits,
            //         level,
            //         @ptrCast(self.tree_at_level(level)),
            //         @ptrCast(self.tree_at_level(level + 1)),
            //     );
            // }
        }

        pub fn set(self: *Self, coord: [3]usize, voxel: PackedVoxel) void {
            self.voxels[to_index(coord)] = voxel;
        }

        // TODO: Determine whether voxels should be stored in z-order.
        //
        // Storing voxels and the tree as though they are on a morton curve
        // might be great for tree generation. Though idk how bad the adverse
        // effects of it would be on rendering and space population.
        //
        // This would especially impact the vectorised generation of voxels, as
        // it would simplify the loading of the register greatly (a single
        // unaligned load as opposed to whatever is going on rn).

        /// Level 1 through `depth` non-inclusive (might be empty).
        tree: [Traits.no_tree_bits / 8]u8,
        /// Level `depth`
        voxels: [Traits.volume]PackedVoxel,
    };
}

test "U8Map constants" {
    try std.testing.expectEqual(2, MkTraits(u8, 1).side_length);
    try std.testing.expectEqual(4, MkTraits(u8, 2).side_length);
    try std.testing.expectEqual(8, MkTraits(u8, 3).side_length);
    try std.testing.expectEqual(16, MkTraits(u8, 4).side_length);
    try std.testing.expectEqual(1, MkTraits(u8, 1).no_tree_bits);
    try std.testing.expectEqual(9, MkTraits(u8, 2).no_tree_bits);
    try std.testing.expectEqual(73, MkTraits(u8, 3).no_tree_bits);
    try std.testing.expectEqual(585, MkTraits(u8, 4).no_tree_bits);
    try std.testing.expectEqual(0, MkTraits(u8, 1).bits_before_level(0));
    try std.testing.expectEqual(1, MkTraits(u8, 1).bits_before_level(1));
    try std.testing.expectEqual(9, MkTraits(u8, 1).bits_before_level(2));
    try std.testing.expectEqual(73, MkTraits(u8, 1).bits_before_level(3));
    try std.testing.expectEqual(585, MkTraits(u8, 1).bits_before_level(4));
}

test generate_tree_scalar_u8 {
    const Map = U8Map(5);

    const bbl = Map.Traits.bits_before_level;

    var map: Map = std.mem.zeroes(Map);

    const level_1 = map.tree[bbl(1) / 8 .. bbl(2) / 8];
    const level_2 = map.tree[bbl(2) / 8 .. bbl(3) / 8];
    const level_3 = map.tree[bbl(3) / 8 .. bbl(4) / 8];
    const level_4 = map.tree[bbl(4) / 8 .. bbl(5) / 8];

    _ = level_1;
    _ = level_2;

    const dummy = PackedVoxel{ .r = 255, .g = 0, .b = 0, .i = 1 };

    map.set(.{0, 0, 0}, dummy);
    map.set(.{1, 0, 0}, dummy);
    map.set(.{1, 1, 0}, dummy);

    map.set(.{0, 2, 0}, dummy);
    map.set(.{2, 2, 0}, dummy);

    map.set(.{0, 0, 2}, dummy);
    map.set(.{0, 2, 2}, dummy);
    map.set(.{2, 2, 2}, dummy);
    map.set(.{4, 2, 2}, dummy);

    generate_tree_scalar_u8(Map.Traits, 4, @ptrCast(level_4.ptr), map.voxels[0..]);
    try std.testing.expectEqualSlices(u8, &.{
        // zig fmt: off
        1,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        1,0,7,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
        // zig fmt: on
    }, level_4);

    generate_tree_scalar_u8(Map.Traits, 3, @ptrCast(level_3.ptr), @ptrCast(level_4.ptr));
    try std.testing.expectEqualSlices(u8, &.{
        // zig fmt: off
        3,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0,
        // zig fmt: on
    }, level_3);
}

