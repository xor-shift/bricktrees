const std = @import("std");

const bit_utils = @import("core").bit_utils;

const curves = @import("curves.zig");

const Brickmap = @import("../brickmap.zig").Brickmap;

pub fn MakeTreeModule(comptime NodeTypeArg: type) type {
    return struct {
        const NodeType = NodeTypeArg;

        const node_bits: comptime_int = @bitSizeOf(NodeType);
        const node_bits_log2: u6 = @ctz(@as(u29, node_bits));
        const node_depth = node_bits_log2 / 3;

        inline fn tree_levels(comptime map_depth: usize) usize {
            std.debug.assert((map_depth % node_depth) == 0);

            return map_depth / node_depth;
        }

        inline fn bits_before_level(comptime tree_level: u6) usize {
            return bit_utils.power_sum(usize, tree_level, node_bits_log2);
        }

        inline fn bits_at_level(comptime tree_level: u6) usize {
            return 1 << (tree_level * node_bits_log2);
        }

        /// 8^0 + 8^1 + ... + 8^(depth - 1)
        /// remember: depth is the depth of the _brickmap_, not the tree
        pub inline fn tree_bits(comptime map_depth: u6) usize {
            return bits_before_level(tree_levels(map_depth));
        }

        pub fn Bricktree(comptime map_depth: usize) type {
            return [tree_bits(map_depth) / @bitSizeOf(NodeType)]NodeType;
        }

        /// Checkes whether the element (be it a voxel or a tree bit) at `index` is
        /// nonzero.
        inline fn element_check(
            comptime map_depth: u6,
            comptime tree_level: u6,
            brickmap: *const Brickmap(map_depth),
            output: *const Bricktree(map_depth),
            coords: [3]usize,
            comptime curve: type,
        ) bool {
            std.debug.assert(tree_level <= tree_levels(map_depth));

            if (tree_level == tree_levels(map_depth)) {
                // voxels are always raster
                const index = curves.raster.forward(tree_level * node_depth, coords);
                return @as(u32, @bitCast(brickmap.c_flat()[index])) != 0;
            }

            const index = curve.forward(tree_level * node_depth, coords);
            const global_bit_offset = (bits_before_level(tree_level) - 1) + index;
            const local_bit_offset = global_bit_offset % node_bits;

            const sample = output[global_bit_offset / node_bits];
            return ((sample >> @intCast(local_bit_offset)) & 1) != 0;
        }

        inline fn occupancy_check(
            comptime map_depth: u6,
            comptime tree_level: u6,
            brickmap: *const Brickmap(map_depth),
            output: *const Bricktree(map_depth),
            coords: [3]usize,
            comptime curve: type,
        ) bool {
            std.debug.assert(tree_level < tree_levels(map_depth));

            const coords_expanded = [_]usize{
                coords[0] << node_depth,
                coords[1] << node_depth,
                coords[2] << node_depth,
            };

            for (0..node_bits) |i| {
                const m = (@as(usize, 1) << node_depth) - 1;
                const inner_coords = [_]usize{
                    coords_expanded[0] + ((i >> (0 * node_depth)) & m),
                    coords_expanded[1] + ((i >> (1 * node_depth)) & m),
                    coords_expanded[2] + ((i >> (2 * node_depth)) & m),
                };

                // std.log.debug("chk for {any} @{d}, idx {d} -> {any}", .{
                //     coords,
                //     tree_level,
                //     i,
                //     inner_coords,
                // });

                if (element_check(map_depth, tree_level + 1, brickmap, output, inner_coords, curve)) {
                    return true;
                }
            }

            return false;
        }

        fn make_level(
            comptime map_depth: u6,
            comptime tree_level: u6,
            brickmap: *const Brickmap(map_depth),
            output: *Bricktree(map_depth),
            comptime curve: type,
        ) void {
            for (0..bits_at_level(tree_level)) |output_bit_idx| {
                const coords = curve.backward(tree_level * node_depth, output_bit_idx);
                const occupied = occupancy_check(map_depth, tree_level, brickmap, output, coords, curve);

                // std.log.debug("@{d}: {any} (for {d})", .{tree_level, coords, output_bit_idx});

                if (occupied) {
                    const global_bit_idx = (bits_before_level(tree_level) - 1) + output_bit_idx;

                    const global_word_idx = global_bit_idx / node_bits;
                    const local_bit_idx = global_bit_idx % node_bits;

                    output[global_word_idx] |= @as(NodeType, 1) << @intCast(local_bit_idx);
                }
            }
        }

        /// `output` must be zero-filled
        pub fn make_tree_inplace(comptime map_depth: u6, brickmap: *const Brickmap(map_depth), output: *Bricktree(map_depth), comptime curve: type) void {
            inline for (1..tree_levels(map_depth)) |i| {
                // std.log.debug("generating {d}", .{i});
                const level = tree_levels(map_depth) - i;
                make_level(map_depth, level, brickmap, output, curve);
            }
        }

        pub fn make_tree(comptime map_depth: u6, brickmap: *const Brickmap(map_depth), alloc: std.mem.Allocator, comptime curve: type) !*Bricktree(map_depth) {
            const ret = try alloc.create(Bricktree(map_depth));
            @memset(ret[0..], 0);

            make_tree_inplace(map_depth, brickmap, ret, curve);

            return ret;
        }
    };
}
