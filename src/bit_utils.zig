const std = @import("std");

/// `upto` is not inclusive
pub fn power_sum(comptime T: type, upto: T, base_log_2: u6) T {
    const a = ((@as(T, 1) << @as(u6, @intCast(base_log_2 * upto))) - 1);
    const b = (@as(T, 1) << base_log_2) - 1;

    return a / b;
}

test power_sum {
    try std.testing.expectEqual(0, power_sum(usize, 0, 1));
    try std.testing.expectEqual(1, power_sum(usize, 1, 1));
    try std.testing.expectEqual(3, power_sum(usize, 2, 1));
    try std.testing.expectEqual(7, power_sum(usize, 3, 1));
    try std.testing.expectEqual(15, power_sum(usize, 4, 1));
    try std.testing.expectEqual(31, power_sum(usize, 5, 1));
    try std.testing.expectEqual(0, power_sum(usize, 0, 3));
    try std.testing.expectEqual(1, power_sum(usize, 1, 3));
    try std.testing.expectEqual(9, power_sum(usize, 2, 3));
    try std.testing.expectEqual(73, power_sum(usize, 3, 3));
    try std.testing.expectEqual(585, power_sum(usize, 4, 3));
    try std.testing.expectEqual(4681, power_sum(usize, 5, 3));
}

pub const StuffDirection = enum {
    left,
    right,
};

pub fn stuff_zeroes(
    comptime direction: StuffDirection,
    comptime T: type,
    to: T,
    group_ct: std.meta.Int(.unsigned, @ctz(@as(u16, @bitSizeOf(T)))),
    group_sz: std.meta.Int(.unsigned, @ctz(@as(u16, @bitSizeOf(T)))),
    zero_ct: std.meta.Int(.unsigned, @ctz(@as(u16, @bitSizeOf(T)))),
) T {
    const Sz = std.meta.Int(.unsigned, @ctz(@as(u16, @bitSizeOf(T))));

    var ret: T = 0;

    const group_mask: T = (@as(T, 1) << (group_sz)) - 1;

    for (0..group_ct) |i| {
        const group_no: Sz = @intCast(i);
        const group = (to >> (group_sz * group_no)) & group_mask;

        const rs = if (direction == .left)
            (group_sz + zero_ct) * group_no
        else
            (zero_ct + group_sz) * group_no + zero_ct;

        ret |= group << rs;
    }

    return ret;
}

test stuff_zeroes {
    try std.testing.expectEqual(0xF0F0F, stuff_zeroes(.left, u32, 0xFFF, 3, 4, 4));
    try std.testing.expectEqual(0x3C78F, stuff_zeroes(.left, u32, 0xFFF, 3, 4, 3));
    try std.testing.expectEqual(0xF3CF, stuff_zeroes(.left, u32, 0xFFF, 3, 4, 2));
    try std.testing.expectEqual(0x3DEF, stuff_zeroes(.left, u32, 0xFFF, 3, 4, 1));

    try std.testing.expectEqual(0xF0F0F0, stuff_zeroes(.right, u32, 0xFFF, 3, 4, 4));
    try std.testing.expectEqual(0x1E3C78, stuff_zeroes(.right, u32, 0xFFF, 3, 4, 3));
    try std.testing.expectEqual(0x3CF3C, stuff_zeroes(.right, u32, 0xFFF, 3, 4, 2));
    try std.testing.expectEqual(0x7BDE, stuff_zeroes(.right, u32, 0xFFF, 3, 4, 1));
}

// by far the worst ratio of lines written to minutes spent in the whole program
// took 2 people like 40 mins
pub fn funny_merge_64(v: u64) u8 {
    var w = v;

    w |= ((w & 0xAAAAAAAAAAAAAAAA) >> 1) | ((w & 0x5555555555555555) << 1);
    w |= ((w & 0xCCCCCCCCCCCCCCCC) >> 2) | ((w & 0x3333333333333333) << 2);
    w |= ((w & 0xF0F0F0F0F0F0F0F0) >> 4) | ((w & 0x0F0F0F0F0F0F0F0F) << 4);

    w = (w & 0x8040_2010_0804_0201) *% 0x0101010101010101;

    return @intCast(w >> 56);
}

test funny_merge_64 {
    try std.testing.expectEqual(0b10101010, funny_merge_64(0x0100_0200_3000_4000));
}
