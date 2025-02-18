const std = @import("std");

const bit_utils = @import("core").bit_utils;

const Brickmap = @import("../brickmap.zig").Brickmap;

pub const NodeType = u64;

const node_bits_log2: u6 = @ctz(@as(u29, @bitSizeOf(NodeType)));
const level_bit_depth: u6 = node_bits_log2 / 3;

inline fn bits_before_level(comptime level: u6) usize {
    if ((level % level_bit_depth) != 0) {
        @compileError(std.fmt.comptimePrint("the level {d} is invalid. levels must be aligned to {d}", .{
            level,
            (level % level_bit_depth),
        }));
    }

    return bit_utils.power_sum(usize, level / level_bit_depth, 6);
}

inline fn bits_at_level(comptime level: u6) usize {
    if ((level % level_bit_depth) != 0) {
        @compileError(std.fmt.comptimePrint("the level {d} is invalid. levels must be aligned to {d}", .{
            level,
            (level % level_bit_depth),
        }));
    }

    return 1 << ((level / level_bit_depth) * 6);
}

/// 8^0 + 8^1 + ... + 8^(depth - 1)
/// remember: depth is the depth of the _brickmap_, not the tree
pub inline fn tree_bits(comptime depth: u6) usize {
    return bits_before_level(depth / level_bit_depth);
}

pub fn Bricktree(comptime depth: usize) type {
    return [tree_bits(depth) / @bitSizeOf(NodeType)]NodeType;
}
