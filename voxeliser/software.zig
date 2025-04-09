const std = @import("std");

const core = @import("core");
const wgm = @import("wgm");

const common = @import("common.zig");

const OBJFile = @import("qov").OBJFile;

test {
    std.testing.refAllDecls(common);
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 6) {
        const process_name = if (args.len == 0) "voxeliser" else args[0];
        std.log.err("usage: {s} <width> <height> <depth> in(.obj) out(.bvox)", .{process_name});
        return;
    }

    const dims: [3]usize = .{
        try std.fmt.parseInt(usize, args[1], 10),
        try std.fmt.parseInt(usize, args[2], 10),
        try std.fmt.parseInt(usize, args[3], 10),
    };

    const in_filename = args[4];
    const out_filename = args[5];

    const LoadStatusCtx = struct {
        in_filename: []const u8,
    };
    const obj_file = try OBJFile.from_file(in_filename, 16, alloc, LoadStatusCtx{
        .in_filename = in_filename,
    }, struct {
        pub fn aufruf(ctx: LoadStatusCtx, status: OBJFile.LoadStatus) void {
            switch (status) {
                .start => std.log.debug("loading {s}...", .{ctx.in_filename}),
                .parsed => std.log.debug("parsed everything", .{}),
                .normalised => std.log.debug("normalised the vertices", .{}),
                .constructed_tree => std.log.debug("constructed the tree", .{}),
            }
        }
    }.aufruf);
    defer obj_file.deinit();

    const dims_vec: @Vector(3, f32) = @floatFromInt(@as(@Vector(3, usize), dims));
    const model_origin: @Vector(3, f32) = obj_file.physical_range[0];
    const model_size: @Vector(3, f32) = wgm.sub(obj_file.physical_range[1], obj_file.physical_range[0]);
    const norm_vertices = try alloc.alloc(@Vector(3, f32), obj_file.vertices.len);
    defer alloc.free(norm_vertices);
    for (obj_file.vertices, 0..) |vert, i| norm_vertices[i] = (vert - model_origin) * dims_vec / model_size;

    if (false) {
        var iter = obj_file.iterate();
        while (iter.next()) |res| {
            const node = obj_file.tree[res.node];
            std.log.debug("{s}{d} {d}..{d} ({d}) {any}", .{
                "        "[0..res.depth],
                res.node,
                node.face_offset,
                node.face_offset + node.face_count,
                node.face_count,
                res.bounds,
            });
        }
    }

    std.log.debug("{d} vertices", .{obj_file.vertices.len});
    std.log.debug("{d} faces", .{obj_file.faces.len});
    std.log.debug("{any} to {any} ({d:.4} {d:.4} {d:.4})", .{
        obj_file.physical_range[0],
        obj_file.physical_range[1],

        wgm.sub(obj_file.physical_range[1], obj_file.physical_range[0])[0],
        wgm.sub(obj_file.physical_range[1], obj_file.physical_range[0])[1],
        wgm.sub(obj_file.physical_range[1], obj_file.physical_range[0])[2],
    });
    std.log.debug("{d} tree nodes", .{obj_file.tree.len});

    var out_bvox = try std.fs.cwd().createFile(out_filename, .{});
    defer out_bvox.close();

    _ = std.os.linux.fallocate(out_bvox.handle, 0o664, 0, @intCast(dims[2] * dims[1] * dims[0]));

    var timer = try std.time.Timer.start();

    const impl = @import("software/backward.zig");
    const swcommon = @import("software/common.zig");

    var pool = try swcommon.Pool(impl).init(15, alloc, impl.producer, impl.worker);
    defer alloc.destroy(pool);
    defer pool.deinit();

    const cc: swcommon.CommonContext(impl) = .{
        .out = out_bvox,

        .alloc = alloc,
        .pool = pool,

        .timer = try std.time.Timer.start(),

        .dims = dims,
        .file = &obj_file,
        .norm_vertices = norm_vertices,
    };

    var context = try impl.Context.init(cc);
    defer context.deinit();

    pool.begin_work(&context);

    while (pool.get_result()) |res| {
        try context.process_result(res.for_work, res.result);
    }

    const elapsed_ns = timer.read();
    try std.fmt.format(std.io.getStdOut().writer(), "\n{d:.5}ms elapsed\n", .{
        @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_ms,
    });
}
