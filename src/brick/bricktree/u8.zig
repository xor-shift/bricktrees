const std = @import("std");

const bit_utils = @import("../../bit_utils.zig");

const Brickmap = @import("../brickmap.zig").Brickmap;

inline fn bits_before_level(comptime level: u6) usize {
    return bit_utils.power_sum(usize, level, 3);
}

inline fn bits_at_level(comptime level: u6) usize {
    return 1 << (level * 3);
}

/// 8^0 + 8^1 + ... + 8^(depth - 1)
/// remember: depth is the depth of the _brickmap_, not the tree
pub inline fn tree_bits(comptime depth: u6) usize {
    return bits_before_level(depth);
}

/// Checkes whether the element (be it a voxel or a tree bit) at `index` is
/// nonzero.
inline fn element_check(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *const [tree_bits(depth) / 8]u8,
    index: usize,
) bool {
    std.debug.assert(level <= depth);

    if (level == depth) {
        return @as(u32, @bitCast(brickmap.c_flat()[index])) != 0;
    }

    const global_bit_offset = (bits_before_level(level) - 1) + index;
    const local_bit_offset: u3 = @intCast(global_bit_offset % 8);

    const sample = output[global_bit_offset / 8];
    return ((sample >> local_bit_offset) & 1) != 0;
}

/// Checks whether the bit at index `bit_to_check` on `level` should be set to 1
inline fn occupancy_check(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *const [tree_bits(depth) / 8]u8,
    bit_to_check: usize,
) bool {
    std.debug.assert(level < depth);

    const expanded_idx = bit_utils.stuff_zeroes(.right, usize, bit_to_check, 3, level, 1);

    const next_level_bitor_values: [8]usize = comptime .{
        bit_utils.stuff_zeroes(.left, usize, 0b000, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b001, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b010, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b011, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b100, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b101, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b110, 3, 1, level),
        bit_utils.stuff_zeroes(.left, usize, 0b111, 3, 1, level),
    };

    for (0..8) |i| {
        const next_level_index = expanded_idx | next_level_bitor_values[i];

        if (element_check(depth, level + 1, brickmap, output, next_level_index)) {
            return true;
        }
    }

    return false;
}

fn make_level(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *[tree_bits(depth) / 8]u8,
) void {
    for (0..bits_at_level(level)) |output_bit_idx| {
        const occupied = occupancy_check(depth, level, brickmap, output, output_bit_idx);

        if (occupied) {
            const global_bit_idx = (bits_before_level(level) - 1) + output_bit_idx;

            output[global_bit_idx / 8] |= @as(u8, 1) << @as(u3, @intCast(global_bit_idx % 8));
        }
    }
}

pub const Settings = struct {
    pub const Curve = enum {
        raster,
        last_layer_morton,
        morton,
    };

    curve: Curve = .raster,
};

/// `output` must be zero-filled
pub fn make_tree_inplace(
    comptime depth: u6,
    brickmap: *const Brickmap(depth),
    output: *[tree_bits(depth) / 8]u8,
) void {
    inline for (1..depth) |i| {
        const level = depth - i;
        make_level(depth, level, brickmap, output);
    }
}

pub fn make_tree(
    comptime depth: u6,
    brickmap: *const Brickmap(depth),
    alloc: std.mem.Allocator,
) !*[tree_bits(depth) / 8]u8 {
    const ret = try alloc.create([tree_bits(depth) / 8]u8);
    @memset(ret[0..], 0);

    make_tree_inplace(depth, brickmap, ret);

    return ret;
}
