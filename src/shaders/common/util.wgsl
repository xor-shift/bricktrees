/* fn all_bits_are_right_leaning_8(val: u32) -> bool {
    let rs1 = (val >> 1) | val;
    let rs2 = (rs1 >> 2) | rs1;
    let rs4 = (rs2 >> 4) | rs2;

    return rs4 == val;
} */

fn all_bits_are_right_leaning(val: u32) -> bool {
    return ((val + 1) & val) == 0;
}

// 0x1000023F -> 0b10000111
fn funny_merge_4_32(val: u32) -> u32 {
    let or1 = val | ((val & 0xAAAAAAA) >> 1) | ((val & 0x55555555) << 1);
    let or2 = or1 | ((or1 & 0xCCCCCCC) >> 2) | ((or1 & 0x33333333) << 2);
    // 0xF0000FFF

    let res_hi = (((or2 >> 16) & 0x8421) * 0x1111) >> 12;
    let res_lo = (((or2 >>  0) & 0x8421) * 0x1111) >> 12;

    return (res_hi << 4) | res_lo;
}

// 0x1000023F -> 0b1011
fn funny_merge_8_32(val: u32) -> u32 {
    let or1 = val | ((val & 0xAAAAAAA) >> 1) | ((val & 0x55555555) << 1);
    let or2 = or1 | ((or1 & 0xCCCCCCC) >> 2) | ((or1 & 0x33333333) << 2);
    let or4 = or2 | ((or2 & 0xF0F0F0F) >> 4) | ((or2 & 0x0F0F0F0F) << 4);
    // 0xFF00FFFF

    let res = (or4 & 0x08040201) * 0x01010101;

    return res >> 28;
}

/// `upto` is not inclusive
fn power_sum(upto: u32, base_log_2: u32) -> u32 {
    let a = (1u << (base_log_2 * upto)) - 1u;
    let b = (1u << base_log_2) - 1;

    return a / b;
}

fn swap_endian(v: u32) -> u32 {
    var w = v;
    w = ((w & 0xFFFF0000u) >> 16u) | ((w & 0x0000FFFFu) << 16u);
    w = ((w & 0xFF00FF00u) >> 8u ) | ((w & 0x00FF00FFu) << 8u );

    return w;
}
