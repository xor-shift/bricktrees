const std = @import("std");

const wgm = @import("wgm");

const common = @import("../common.zig");
const swcommon = @import("common.zig");

const OBJFile = @import("qov").OBJFile;

const Self = @This();

pub const Context = struct {
    const Pool = swcommon.Pool(Self);

    pub fn init(cc: swcommon.CommonContext(Self)) !Context {
        for (cc.pool.result_storage) |storage| {
            storage.row = try cc.alloc.alloc(u32, cc.dims[0]);
        }

        return .{
            .cc = cc,
        };
    }

    pub fn deinit(self: *Context) void {
        defer for (self.cc.pool.result_storage) |storage| self.cc.alloc.free(storage.row);
    }

    pub fn process_result(self: *Context, for_work: Work, result: *Result) !void {
        const out_start = wgm.to_idx([_]usize{ 0, for_work.yz[0], for_work.yz[1] }, self.cc.dims) * 4;
        try self.cc.out.seekTo(@intCast(out_start));
        try self.cc.out.writeAll(std.mem.sliceAsBytes(result.row));
    }

    cc: swcommon.CommonContext(Self),

    yz: [2]usize = .{ 0, 0 },
};

pub const Work = struct {
    yz: [2]usize,
};

pub const Result = struct {
    row: []u32,
};

pub fn producer(ctx: *Context) ?Work {
    if (ctx.yz[1] >= ctx.cc.dims[2]) return null;

    const ret = ctx.yz;
    ctx.yz[0] += 1;
    if (ctx.yz[0] >= ctx.cc.dims[1]) {
        ctx.yz[0] = 0;
        ctx.yz[1] += 1;
    }

    swcommon.progress(
        ctx.cc.timer.read(),
        ctx.yz[0] + ctx.yz[1] * ctx.cc.dims[1],
        ctx.cc.dims[1] * ctx.cc.dims[2],
    );

    return .{ .yz = ret };
}

pub fn worker(ctx: *Context, out_result: *Result, work: Work) void {
    for (0..ctx.cc.dims[0]) |o_x| {
        const out_coords: [3]usize = .{ o_x, work.yz[0], work.yz[1] };
        const out_index = wgm.to_idx(out_coords, ctx.cc.dims);
        _ = out_index;

        const model_size: @Vector(3, f32) = wgm.sub(ctx.cc.file.physical_range[1], ctx.cc.file.physical_range[0]);

        // const dims_vec: @Vector(3, f32) = @floatFromInt(@as(@Vector(3, usize), ctx.cc.dims));
        // const model_origin: @Vector(3, f32) = ctx.cc.file.physical_range[0];
        // const out_voxel_sz = dims_vec / model_size;

        const res = blk: {
            const iter_range: OBJFile.CoordinateRange = .{
                .start = wgm.add(
                    wgm.mulew(wgm.div(
                        wgm.sub(wgm.lossy_cast(f32, out_coords), 0.01),
                        wgm.lossy_cast(f32, ctx.cc.dims),
                    ), @as([3]f32, model_size)),
                    ctx.cc.file.physical_range[0],
                ),
                .end = wgm.add(
                    wgm.mulew(wgm.div(
                        wgm.lossy_cast(f32, wgm.add(out_coords, 1)),
                        wgm.lossy_cast(f32, ctx.cc.dims),
                    ), @as([3]f32, model_size)),
                    ctx.cc.file.physical_range[0],
                ),
            };
            // std.log.debug("{any}", .{iter_range});

            var iter = ctx.cc.file.iterate_range(iter_range);
            while (iter.next()) |iter_res| {
                const node = ctx.cc.file.tree[iter_res.node];

                const faces = ctx.cc.file.faces[node.face_offset .. node.face_offset + node.face_count];

                for (faces, 0..) |indices, local_offset| {
                    const face: [3]@Vector(3, f32) = .{
                        ctx.cc.norm_vertices[indices[0]],
                        ctx.cc.norm_vertices[indices[1]],
                        ctx.cc.norm_vertices[indices[2]],
                    };

                    const res = common.intersects_voxel(
                        f32,
                        face,
                        @as(@Vector(3, f32), @floatFromInt(@as(@Vector(3, usize), out_coords))),
                        false,
                    );
                    if (res) break :blk node.face_offset + local_offset;
                }
            }

            break :blk null;
        };

        out_result.row[o_x] = if (res) |v| @intCast(v + 1) else 0;
    }
}
