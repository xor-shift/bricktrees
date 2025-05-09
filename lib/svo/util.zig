const std = @import("std");

const core = @import("core");
const wgm = @import("wgm");

/// unfortunately not inplace
pub fn mortonify(comptime T: type, depth: u6, out: [*]T, in: [*]const T) void {
    const morton = core.curves.morton;

    const sl = @as(usize, 1) << depth;
    const msl = @as(usize, 1) << (depth - 1);
    for (0..msl) |z| for (0..msl) |y| for (0..msl) |x| {
        const i = (x + (y + z * sl) * sl) * 2;
        const k = morton.forward(12, [_]usize{ x, y, z });

        const v: [8]T = .{
            in[i],
            in[i + 1],
            in[i + sl],
            in[i + sl + 1],
            in[i + sl * sl],
            in[i + sl * sl + 1],
            in[i + sl * sl + sl],
            in[i + sl * sl + sl + 1],
        };

        @memcpy(out[k * 8 .. (k + 1) * 8], v[0..]);
    };
}

test mortonify {
    const alloc = std.testing.allocator;

    const depth: u6 = 3;
    const dims: [3]usize = .{@as(usize, 1) << depth} ** 3;

    const in = try alloc.alloc(u32, dims[2] * dims[1] * dims[0]);
    defer alloc.free(in);
    for (0..in.len) |i| in[i] = @intCast(i);

    const out = try alloc.alloc(u32, dims[2] * dims[1] * dims[0]);
    defer alloc.free(out);

    mortonify(u32, depth, out.ptr, in.ptr);

    // const writer = std.io.getStdOut().writer();
    const writer = std.io.null_writer;
    for (0..dims[2]) |z| for (0..dims[1]) |y| for (0..dims[0]) |x| {
        if (x == 0) writer.writeByte('\n') catch {};
        if (y == 0 and x == 0) writer.writeByte('\n') catch {};

        std.fmt.format(writer, "{d: >4}", .{
            out[wgm.to_idx([_]usize{ x, y, z }, dims)],
        }) catch {};
    };
}
