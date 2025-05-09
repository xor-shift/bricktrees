const std = @import("std");

const core = @import("core");
const qov = @import("qov");
const wgm = @import("wgm");

pub const misc = @import("misc.zig");
const util = @import("util.zig");

const PackedVoxel = qov.PackedVoxel;
pub const SVOBuilder = @import("SVOBuilder.zig");
pub const SVOIterator = @import("SVOIterator.zig");

const InCoreFinishContext = SVOBuilder.InCoreFinishContext;

test {
    std.testing.refAllDecls(misc);
    std.testing.refAllDecls(util);

    std.testing.refAllDecls(SVOBuilder);
    std.testing.refAllDecls(SVOIterator);
}

/// calls `create_svo_context` with an `InCoreFinishContext`
pub fn create_svo(
    depth: u6,
    block_depth: u6,
    alloc: std.mem.Allocator,
    context: anytype,
    comptime block_fn: fn (
        ctx: @TypeOf(context),
        out_depth: u6,
        block_coords: [3]usize,
        out: [*]PackedVoxel,
    ) void,
) ![]u32 {
    var finish_ctx = InCoreFinishContext.init(alloc);
    defer finish_ctx.deinit();

    try create_svo_context(depth, block_depth, alloc, context, block_fn, &finish_ctx);

    return try finish_ctx.to_slice();
}

pub fn create_svo_context(depth: u6, block_depth: u6, alloc: std.mem.Allocator, context: anytype, comptime block_fn: fn (
    ctx: @TypeOf(context),
    out_depth: u6,
    block_coords: [3]usize,
    out: [*]PackedVoxel,
) void, finish_ctx: anytype) !void {
    // @setRuntimeSafety(!@import("builtin").is_test);
    std.debug.assert(depth >= block_depth);

    const morton_block = try alloc.alloc(PackedVoxel, @as(usize, 1) << (3 * block_depth));
    defer alloc.free(morton_block);

    const out_block = try alloc.alloc(PackedVoxel, @as(usize, 1) << (3 * block_depth));
    defer alloc.free(out_block);

    var builder = try SVOBuilder.init(alloc);
    defer builder.deinit();

    for (0..@as(usize, 1) << (3 * (depth - block_depth))) |i| {
        const coords = core.curves.morton.backward(0, i);
        // std.log.debug("{any}", .{coords});

        @call(.auto, block_fn, .{
            context,
            block_depth,
            coords,
            out_block.ptr,
        });

        util.mortonify(
            PackedVoxel,
            block_depth,
            morton_block.ptr,
            out_block.ptr,
        );

        for (0..morton_block.len / 8) |j| {
            var mini_block: [8]PackedVoxel = undefined;
            @memcpy(mini_block[0..], morton_block[j * 8 .. (j + 1) * 8]);
            try builder.submit(mini_block);
        }
    }

    return try builder.finish_context(finish_ctx);
}

test create_svo {
    const alloc = std.testing.allocator;

    const context: misc.SphereGenerator = .{
        .center = .{8} ** 3,
        .radius = 7.5,
        .material = .{
            .r = 0x55,
            .g = 0xAA,
            .b = 0x55,
            .i = 0xAA,
        },
    };

    const res = try create_svo(4, 4, alloc, context, misc.SphereGenerator.fun);
    defer alloc.free(res);
    // std.log.debug("{d}", .{res.len});

    const expected = try alloc.alloc(PackedVoxel, 16 * 16 * 16);
    defer alloc.free(expected);
    @memset(expected, PackedVoxel.air);
    context.fun(4, .{ 0, 0, 0 }, expected.ptr);

    const expected_morton = try alloc.alloc(PackedVoxel, 16 * 16 * 16);
    defer alloc.free(expected_morton);
    util.mortonify(PackedVoxel, 4, expected_morton.ptr, expected.ptr);

    const out = try alloc.alloc(PackedVoxel, 16 * 16 * 16);
    defer alloc.free(out);
    @memset(out, PackedVoxel.air);

    var iter = SVOIterator.init(res, 4);
    while (iter.next()) |v| {
        if (false) switch (v) {
            .Node => |w| {
                std.log.debug("{s}node: {any}", .{
                    ("*" ** 8)[0..w.depth],
                    w.extents,
                });
            },
            .Voxel => |w| {
                std.log.debug("{s}voxel: {any}, {X:0>8}", .{
                    ("*" ** 8)[0..w.depth],
                    w.extents,
                    @as(u32, @bitCast(w.material)),
                });
            },
        };

        const at, const material = switch (v) {
            .Node => continue,
            .Voxel => |w| .{ w.extents[0], w.material },
        };

        out[wgm.to_idx(at, .{ 16, 16, 16 })] = material;
    }

    const writer = std.io.getStdOut().writer();
    // const writer = std.io.null_writer;
    for (0..16) |z| for (0..16) |y| for (0..16) |x| {
        if (x == 0) try writer.writeByte('\n');
        if (x == 0 and y == 0) try writer.writeByte('\n');

        const mat: u32 = @bitCast(out[wgm.to_idx([_]usize{ x, y, z }, .{ 16, 16, 16 })]);
        try writer.writeByte(if (mat == 0) '#' else '.');
    };
}
