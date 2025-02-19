const std = @import("std");

const bit_utils = @import("core").bit_utils;

const Brickmap = @import("../brickmap.zig").Brickmap;
const Traits = @import("common.zig").Traits;

pub const NodeType = u8;

const node_bits_log2: u6 = @ctz(@as(u29, @bitSizeOf(NodeType)));
const level_bit_depth: u6 = node_bits_log2 / 2;

inline fn bits_before_level(comptime level: u6) usize {
    return bit_utils.power_sum(usize, level, node_bits_log2);
}

inline fn bits_at_level(comptime level: u6) usize {
    return 1 << (level * node_bits_log2);
}

/// 8^0 + 8^1 + ... + 8^(depth - 1)
/// remember: depth is the depth of the _brickmap_, not the tree
pub inline fn tree_bits(comptime depth: u6) usize {
    return bits_before_level(depth);
}

pub fn Bricktree(comptime depth: usize) type {
    return [tree_bits(depth) / 8]u8;
}

/// If, for any `n`, the bit depth of `coords[n]` exceeds `depth`, the behaviour
/// is undefined. Likewise, if the bit depth of `index` exceeds `depth * 3`,
/// the behaviour is undefined.
pub const curves = struct {
    pub const raster = struct {
        inline fn forward(comptime depth: usize, coords: [3]usize) usize {
            return 0 //
            | (coords[0] << (0 * depth)) //
            | (coords[1] << (1 * depth)) //
            | (coords[2] << (2 * depth));
        }

        inline fn backward(comptime depth: usize, index: usize) [3]usize {
            const mask = (@as(usize, 1) << depth) - 1;
            return .{
                (index >> (0 * depth)) & mask,
                (index >> (1 * depth)) & mask,
                (index >> (2 * depth)) & mask,
            };
        }
    };

    test raster {
        try std.testing.expectEqual(0x07, raster.forward(1, .{ 1, 1, 1 }));
        try std.testing.expectEqual(0x15, raster.forward(2, .{ 1, 1, 1 }));
        try std.testing.expectEqual(0x16, raster.forward(2, .{ 2, 1, 1 }));
        try std.testing.expectEqual(0x25, raster.forward(2, .{ 1, 1, 2 }));
        try std.testing.expectEqual(0x3F, raster.forward(2, .{ 3, 3, 3 }));
    }

    pub const morton = struct {
        inline fn forward(comptime depth: usize, coords: [3]usize) usize {
            const T = @Type(std.builtin.Type{ .Int = .{
                .bits = @intCast(depth),
                .signedness = .unsigned,
            } });

            const pad = bit_utils.stuff_3_zeroes_left;

            const x: usize = @intCast(pad(@as(T, @intCast(coords[0]))));
            const y: usize = @intCast(pad(@as(T, @intCast(coords[1]))));
            const z: usize = @intCast(pad(@as(T, @intCast(coords[2]))));

            return x | (y << 1) | (z << 2);
        }

        inline fn backward(comptime depth: usize, index: usize) [3]usize {
            _ = depth;

            const k: u64 = 0x1249_2492_4924_9249;
            const x_bits: u63 = @intCast((index >> 0) & k);
            const y_bits: u63 = @intCast((index >> 1) & k);
            const z_bits: u63 = @intCast((index >> 2) & k);

            const x: usize = @intCast(bit_utils.unstuff_3_zeroes_left(x_bits));
            const y: usize = @intCast(bit_utils.unstuff_3_zeroes_left(y_bits));
            const z: usize = @intCast(bit_utils.unstuff_3_zeroes_left(z_bits));

            return .{ x, y, z };
        }
    };

    test morton {
        try std.testing.expectEqual(0b110101, morton.forward(2, .{ 1, 2, 3 }));
        try std.testing.expectEqual([_]usize{ 1, 2, 3 }, morton.backward(2, 0b110101));
    }

    pub const llm = struct {
        inline fn forward(comptime depth: usize, coords: [3]usize) usize {
            // z4 z3 z2 z1 z0  y4 y3 y2 y1 y0  x5 x4 x3 x2 x1 x0
            // z4 z3 z2 z1     y4 y3 y2 y1     x5 x4 x3 x2 x1    z0 y0 x0

            return 0 | //
                (coords[0] & 1) << 0 |
                (coords[1] & 1) << 1 |
                (coords[2] & 1) << 2 |
                (coords[0] >> 1) << (3 + (depth - 1) * 0) |
                (coords[1] >> 1) << (3 + (depth - 1) * 1) |
                (coords[2] >> 1) << (3 + (depth - 1) * 2);
        }

        inline fn backward(comptime depth: usize, index: usize) [3]usize {
            const last_three = index & 7;
            const base_raw = raster.backward(depth - 1, index >> 3);

            return .{
                (base_raw[0] << 1) | ((last_three >> 0) & 1),
                (base_raw[1] << 1) | ((last_three >> 1) & 1),
                (base_raw[2] << 1) | ((last_three >> 2) & 1),
            };
        }
    };

    test llm {
        // 014589CD
        // 2367ABEF
        // 014589CD
        // 2367ABEF
        // ...

        const table = [_][3]usize{
            .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 },
            .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 },
            .{ 2, 0, 0 }, .{ 3, 0, 0 }, .{ 2, 1, 0 }, .{ 3, 1, 0 },
            .{ 2, 0, 1 }, .{ 3, 0, 1 }, .{ 2, 1, 1 }, .{ 3, 1, 1 },
            .{ 4, 0, 0 }, .{ 5, 0, 0 }, .{ 4, 1, 0 }, .{ 5, 1, 0 },
            .{ 4, 0, 1 }, .{ 5, 0, 1 }, .{ 4, 1, 1 }, .{ 5, 1, 1 },
            .{ 6, 0, 0 }, .{ 7, 0, 0 }, .{ 6, 1, 0 }, .{ 7, 1, 0 },
            .{ 6, 0, 1 }, .{ 7, 0, 1 }, .{ 6, 1, 1 }, .{ 7, 1, 1 },

            .{ 0, 2, 0 }, .{ 1, 2, 0 }, .{ 0, 3, 0 }, .{ 1, 3, 0 },
            .{ 0, 2, 1 }, .{ 1, 2, 1 }, .{ 0, 3, 1 }, .{ 1, 3, 1 },
            .{ 2, 2, 0 }, .{ 3, 2, 0 }, .{ 2, 3, 0 }, .{ 3, 3, 0 },
            .{ 2, 2, 1 }, .{ 3, 2, 1 }, .{ 2, 3, 1 }, .{ 3, 3, 1 },
            .{ 4, 2, 0 }, .{ 5, 2, 0 }, .{ 4, 3, 0 }, .{ 5, 3, 0 },
            .{ 4, 2, 1 }, .{ 5, 2, 1 }, .{ 4, 3, 1 }, .{ 5, 3, 1 },
            .{ 6, 2, 0 }, .{ 7, 2, 0 }, .{ 6, 3, 0 }, .{ 7, 3, 0 },
            .{ 6, 2, 1 }, .{ 7, 2, 1 }, .{ 6, 3, 1 }, .{ 7, 3, 1 },
        };

        for (0.., table) |i, v| {
            try std.testing.expectEqual(i, llm.forward(3, v));
            try std.testing.expectEqual(v, llm.backward(3, i));
        }
    }
};

test {
    std.testing.refAllDecls(curves);
}

/// Checkes whether the element (be it a voxel or a tree bit) at `index` is
/// nonzero.
inline fn element_check(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *const Bricktree(depth),
    coords: [3]usize,
    comptime curve: type,
) bool {
    std.debug.assert(level <= depth);

    if (level == depth) {
        // voxels are always raster
        const index = curves.raster.forward(level, coords);
        return @as(u32, @bitCast(brickmap.c_flat()[index])) != 0;
    }

    const index = curve.forward(level, coords);
    const global_bit_offset = (bits_before_level(level) - 1) + index;
    const local_bit_offset: u3 = @intCast(global_bit_offset % 8);

    const sample = output[global_bit_offset / 8];
    return ((sample >> local_bit_offset) & 1) != 0;
}

inline fn occupancy_check(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *const Bricktree(depth),
    coords: [3]usize,
    comptime curve: type,
) bool {
    std.debug.assert(level < depth);

    // const expanded_idx = bit_utils.stuff_zeroes(.right, usize, raster_coord_index, 3, level, 1);

    // const next_level_bitor_values: [8]usize = comptime .{
    //     bit_utils.stuff_zeroes(.left, usize, 0b000, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b001, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b010, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b011, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b100, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b101, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b110, 3, 1, level),
    //     bit_utils.stuff_zeroes(.left, usize, 0b111, 3, 1, level),
    // };

    const coords_expanded = [_]usize{
        coords[0] << 1,
        coords[1] << 1,
        coords[2] << 1,
    };

    for (0..8) |i| {
        const inner_coords = [_]usize{
            coords_expanded[0] + ((i >> 0) & 1),
            coords_expanded[1] + ((i >> 1) & 1),
            coords_expanded[2] + ((i >> 2) & 1),
        };

        if (element_check(depth, level + 1, brickmap, output, inner_coords, curve)) {
            return true;
        }
    }

    return false;
}

fn make_level(
    comptime depth: u6,
    comptime level: u6,
    brickmap: *const Brickmap(depth),
    output: *Bricktree(depth),
    comptime curve: type,
) void {
    for (0..bits_at_level(level)) |output_bit_idx| {
        const coords = curve.backward(level, output_bit_idx);
        const occupied = occupancy_check(depth, level, brickmap, output, coords, curve);

        if (occupied) {
            const global_bit_idx = (bits_before_level(level) - 1) + output_bit_idx;

            output[global_bit_idx / 8] |= @as(u8, 1) << @as(u3, @intCast(global_bit_idx % 8));
        }
    }
}

/// `output` must be zero-filled
pub fn make_tree_inplace(
    comptime depth: u6,
    brickmap: *const Brickmap(depth),
    output: *Bricktree(depth),
    comptime curve: type
) void {
    inline for (1..depth) |i| {
        const level = depth - i;
        make_level(depth, level, brickmap, output, curve);
    }
}

pub fn make_tree(
    comptime depth: u6,
    brickmap: *const Brickmap(depth),
    alloc: std.mem.Allocator,
    comptime curve: type
) !*Bricktree(depth) {
    const ret = try alloc.create(Bricktree(depth));
    @memset(ret[0..], 0);

    make_tree_inplace(depth, brickmap, ret, curve);

    return ret;
}

