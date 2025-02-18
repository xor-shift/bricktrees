const std = @import("std");

/// `upto` is not inclusive
pub inline fn power_sum(comptime T: type, upto: T, base_log_2: u6) T {
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

pub inline fn stuff_zeroes(
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
pub inline fn funny_merge_64(v: u64) u8 {
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

inline fn s3zl_impl(v: u4) u12 {
    var w: u48 = @intCast(v);

    w *= 0x001_001_001_001;
    w &= 0x008_004_002_001;
    w *%= 0x001_004_010_040;

    return @intCast(w >> 36);
}

test s3zl_impl {
    const expected_table = [16]u12{
        0b000000000000, 0b000000000001, 0b000000001000, 0b000000001001,
        0b000001000000, 0b000001000001, 0b000001001000, 0b000001001001,
        0b001000000000, 0b001000000001, 0b001000001000, 0b001000001001,
        0b001001000000, 0b001001000001, 0b001001001000, 0b001001001001,
    };

    for (0..16) |i| try std.testing.expectEqual(expected_table[i], s3zl_impl(@as(u4, @intCast(i))));
}

pub inline fn stuff_3_zeroes_left(v: anytype) @Type(std.builtin.Type{ .Int = .{
    .bits = @typeInfo(@TypeOf(v)).Int.bits * 3,
    .signedness = .unsigned,
} }) {
    const T = @TypeOf(v);
    const v_bits = @typeInfo(T).Int.bits;
    const full_nibbles = v_bits / 4;
    const excess_bits = v_bits % 4;

    if (@bitSizeOf(T) <= 4) {
        return @intCast(s3zl_impl(@intCast(v)));
    }

    const Ret = @Type(std.builtin.Type{ .Int = .{
        .bits = v_bits * 3,
        .signedness = .unsigned,
    } });

    var ret: Ret = 0;

    //aaaabbbbccc
    //0   1
    //1   0
    inline for (0..full_nibbles) |i| {
        const j = full_nibbles - i - 1;
        const shr = j * 4 + excess_bits;

        const nibble: u4 = @intCast((v >> @intCast(shr)) & 0xF);
        const padded_nibble: Ret = @intCast(s3zl_impl(nibble));

        ret <<= 12;
        ret |= @intCast(padded_nibble);
    }

    if (excess_bits != 0) {
        const mask = (@as(u4, 1) << excess_bits) - 1;
        const excess = @as(u4, @truncate(v)) & mask;
        const padded_excess: Ret = @intCast(s3zl_impl(excess));

        const omask = (@as(Ret, 1) << (excess_bits * 3)) - 1;
        ret <<= excess_bits * 3;
        ret |= padded_excess & omask;
    }

    return ret;
}

test stuff_3_zeroes_left {
    try std.testing.expectEqual(
        @as(u33, 0b001000001000_001000001000_001000001),
        stuff_3_zeroes_left(@as(u11, 0b1010_1010_101)),
    );
}

inline fn us3zl_impl(v: u12) u4 {
    var w: u48 = @intCast(v);

    // 001001001001 001001001001 001001001001 001001001001
    // 001000000000 000001000000 000000001000 000000000001
    // 001000000000 00x001000000 00xx00001000 00xxx0000001
    // 000100000000 000001000000 000000010000 000000000100

    w *= 0x001_001_001_001;
    w &= 0x200_040_008_001;
    w *%= 0x100_040_010_004;

    return @intCast(w >> 44);
}

test us3zl_impl {
    try std.testing.expectEqual(0b1111, us3zl_impl(0b111111111111));
    try std.testing.expectEqual(0b1111, us3zl_impl(0b001001001001));
    try std.testing.expectEqual(0b0111, us3zl_impl(0b000001001001));
    try std.testing.expectEqual(0b0101, us3zl_impl(0b000001000001));
    try std.testing.expectEqual(0b0000, us3zl_impl(0b000000000000));
    try std.testing.expectEqual(0b0000, us3zl_impl(0b110110110110));
}

pub inline fn unstuff_3_zeroes_left(v: anytype) @Type(std.builtin.Type{ .Int = .{
    .bits = @typeInfo(@TypeOf(v)).Int.bits / 3,
    .signedness = .unsigned,
} }) {
    const T = @TypeOf(v);
    const v_bits = @typeInfo(T).Int.bits;
    std.debug.assert((v_bits % 3) == 0);

    const full_nibbles = v_bits / 12;
    const excess_bits = (v_bits / 3) % 4;

    if (@bitSizeOf(T) <= 12) {
        return @intCast(us3zl_impl(@intCast(v)));
    }

    const ret_bits = v_bits / 3;
    const Ret = @Type(std.builtin.Type{ .Int = .{ .bits = ret_bits, .signedness = .unsigned } });

    var ret: Ret = 0;

    inline for (0..full_nibbles) |i| {
        const j = full_nibbles - i - 1;
        const shr = j * 12 + excess_bits * 3;

        const trinibble: u12 = @intCast((v >> @intCast(shr)) & 0xFFF);
        const nibble: Ret = @intCast(us3zl_impl(trinibble));

        ret <<= 4;
        ret |= @intCast(nibble);
    }

    if (excess_bits != 0) {
        const mask = (@as(u12, 1) << excess_bits) - 1;
        const trinibble = @as(u12, @truncate(v)) & mask;
        const nibble: Ret = @intCast(us3zl_impl(trinibble));

        const omask = (@as(Ret, 1) << (excess_bits)) - 1;
        ret <<= excess_bits;
        ret |= nibble & omask;
    }

    return ret;
}

test unstuff_3_zeroes_left {
    const f = unstuff_3_zeroes_left;
    try std.testing.expectEqual(0b1111, f(@as(u12, 0b111111111111)));
    try std.testing.expectEqual(0b1111, f(@as(u12, 0b001001001001)));
    try std.testing.expectEqual(0b0111, f(@as(u12, 0b000001001001)));
    try std.testing.expectEqual(0b0101, f(@as(u12, 0b000001000001)));
    try std.testing.expectEqual(0b0000, f(@as(u12, 0b000000000000)));
    try std.testing.expectEqual(0b0000, f(@as(u12, 0b110110110110)));

    try std.testing.expectEqual(0b11111111, f(@as(u24, 0b111111111111111111111111)));
    try std.testing.expectEqual(0b11111111, f(@as(u24, 0b001001001001001001001001)));
    try std.testing.expectEqual(0b01110111, f(@as(u24, 0b000001001001000001001001)));
    try std.testing.expectEqual(0b01010101, f(@as(u24, 0b000001000001000001000001)));
    try std.testing.expectEqual(0b00000000, f(@as(u24, 0b000000000000000000000000)));
    try std.testing.expectEqual(0b00000000, f(@as(u24, 0b110110110110110110110110)));

    try std.testing.expectEqual(0b111111111, f(@as(u27, 0b001111111111111111111111111)));
    try std.testing.expectEqual(0b111111111, f(@as(u27, 0b001001001001001001001001001)));
    try std.testing.expectEqual(0b101110111, f(@as(u27, 0b001000001001001000001001001)));
    try std.testing.expectEqual(0b101010101, f(@as(u27, 0b001000001000001000001000001)));
    try std.testing.expectEqual(0b100000000, f(@as(u27, 0b001000000000000000000000000)));
    try std.testing.expectEqual(0b100000000, f(@as(u27, 0b001110110110110110110110110)));
}
