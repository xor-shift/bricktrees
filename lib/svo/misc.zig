const std = @import("std");

const qov = @import("qov");
const wgm = @import("wgm");

const PackedVoxel = qov.PackedVoxel;

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

pub const SphereGenerator = struct {
    center: [3]f32,
    radius: f32,
    material: PackedVoxel,

    pub fn fun(
        ctx: SphereGenerator,
        out_depth: u6,
        block_coords: [3]usize,
        out: [*]PackedVoxel,
    ) void {
        const sl = @as(usize, 1) << out_depth;
        const gl_coord_base = wgm.mulew(block_coords, sl);

        // const writer = std.io.getStdOut().writer();

        for (0..sl) |z| for (0..sl) |y| for (0..sl) |x| {
            const bl_coords = [3]usize{ x, y, z };
            const gl_coords = wgm.add(gl_coord_base, bl_coords);
            const out_idx = wgm.to_idx(bl_coords, [_]usize{sl} ** 3);

            const gl_coords_f = wgm.sub(wgm.lossy_cast(f32, gl_coords), 0.5);
            const dist = wgm.length(wgm.sub(ctx.center, gl_coords_f));
            const within_radius = dist <= ctx.radius;

            out[out_idx] = if (within_radius) ctx.material else PackedVoxel.air;

            // if (x == 0) writer.writeByte('\n') catch {};
            // if (y == 0 and x == 0) writer.writeByte('\n') catch {};
            // writer.writeByte(if (within_radius) '#' else '.') catch {};
        };
    }
};
