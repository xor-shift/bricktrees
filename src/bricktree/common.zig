const bit_utils = @import("core").bit_utils;

pub const Traits = struct {
    NodeType: type,
    node_bits_log2: u6,
    level_bit_depth: u6,

    pub fn init(comptime NodeType: type) Traits {
        const node_bits_log2: u6 = @ctz(@as(u29, @bitSizeOf(NodeType)));

        return .{
            .NodeType = NodeType,
            .node_bits_log2 = node_bits_log2,
            .level_bit_depth = node_bits_log2 / 2,
        };
    }

    inline fn bits_before_level(comptime self: Traits, comptime level: u6) usize {
        return bit_utils.power_sum(usize, level, self.node_bits_log2);
    }

    inline fn bits_at_level(comptime self: Traits, comptime level: u6) usize {
        return 1 << (level * self.node_bits_log2);
    }

    /// 8^0 + 8^1 + ... + 8^(depth - 1)
    /// remember: depth is the depth of the _brickmap_, not the tree
    pub inline fn tree_bits(comptime depth: u6) usize {
        return bits_before_level(depth);
    }
};
