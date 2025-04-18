const std = @import("std");

const wgm = @import("wgm");

pub fn make_sphere(alloc: std.mem.Allocator, depth: u6, radius: f32) ![]u32 {
    const ret = try alloc.alloc(u32, @as(usize, 1) << (3 * depth));

    const sl = @as(usize, 1) << depth;

    for (0..sl) |z| for (0..sl) |y| for (0..sl) |x| {
        const out_coords = [_]usize{ x, y, z };

        const centered_coords = wgm.add(wgm.lossy_cast(f32, out_coords), 0.5);
        const dist = wgm.length(wgm.sub(centered_coords, [_]f32{@floatFromInt(sl / 2)} ** 3));

        ret[wgm.to_idx(out_coords, [_]usize{sl} ** 3)] = if (dist < radius) 1 else 0;
    };

    return ret;
}

