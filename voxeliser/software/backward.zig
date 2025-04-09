const std = @import("std");

const wgm = @import("wgm");

const common = @import("../common.zig");
const swcommon = @import("common.zig");

const OBJFile = @import("qov").OBJFile;

const Self = @This();

pub const Context = struct {
    const Pool = swcommon.Pool(Self);

    pub fn init(cc: swcommon.CommonContext(Self)) !Context {
        const out = try cc.alloc.alloc(u32, cc.dims[2] * cc.dims[1] * cc.dims[0]);
        @memset(out, 0);

        return .{
            .cc = cc,

            .out = out,
        };
    }

    pub fn deinit(self: *Context) void {
        self.cc.out.writeAll(std.mem.sliceAsBytes(self.out)) catch |e| {
            std.log.err("error saving to file: {s}", .{@errorName(e)});
        };

        defer self.cc.alloc.free(self.out);
    }

    pub fn process_result(self: *Context, for_work: Work, result: *Result) !void {
        _ = self;
        _ = for_work;
        _ = result;
    }

    cc: swcommon.CommonContext(Self),

    out: []u32,

    processed: usize = 0,
};

pub const Work = struct {
    range: [2]usize,
};

pub const Result = struct {
    _: void = {},
};

pub fn producer(ctx: *Context) ?Work {
    if (ctx.processed == ctx.cc.file.faces.len) return null;

    const next_range = .{
        ctx.processed,
        @min(ctx.processed + 64, ctx.cc.file.faces.len),
    };
    ctx.processed = next_range[1];

    swcommon.progress(
        ctx.cc.timer.read(),
        ctx.processed,
        ctx.cc.file.faces.len,
    );

    return .{ .range = next_range };
}

pub fn worker(ctx: *Context, _: *Result, work: Work) void {
    const dims_vec: @Vector(3, usize) = ctx.cc.dims;
    const dims_f32: @Vector(3, f32) = @floatFromInt(dims_vec);
    _ = dims_f32;

    for (work.range[0]..work.range[1]) |face_no| {
        const nudge: @Vector(3, f32) = @splat(1.1);
        const one: @Vector(3, usize) = @splat(1);
        _ = one;

        const face = .{
            ctx.cc.norm_vertices[ctx.cc.file.faces[face_no][0]],
            ctx.cc.norm_vertices[ctx.cc.file.faces[face_no][1]],
            ctx.cc.norm_vertices[ctx.cc.file.faces[face_no][2]],
        };

        const bound_min = @min(face[0], @min(face[1], face[2])) / nudge;
        const bound_max = @max(face[0], @max(face[1], face[2])) * nudge;

        const start_voxel: @Vector(3, usize) = @intFromFloat(@floor(bound_min));
        const clamped_start = @min(start_voxel, dims_vec);
        const end_voxel: @Vector(3, usize) = @intFromFloat(@ceil(bound_max));
        const clamped_end = @max(@min(end_voxel, dims_vec), clamped_start);

        const voxel_range = clamped_end - start_voxel;

        for (0..voxel_range[2]) |z| for (0..voxel_range[1]) |y| for (0..voxel_range[0]) |x| {
            const offset: @Vector(3, usize) = .{ x, y, z };
            const voxel_coords = start_voxel + offset;

            const res = common.intersects_voxel(
                f32,
                face,
                @floatFromInt(voxel_coords),
                false,
            );

            if (res) {
                const val: u32 = @intCast(face_no + 1);
                const out = &ctx.out[wgm.to_idx(@as([3]usize, voxel_coords), ctx.cc.dims)];
                @atomicStore(u32, out, val, .unordered);
            }
        };
    }
}
