const std = @import("std");

const qov = @import("qov");
const svo = @import("svo");
const wgm = @import("wgm");

const PackedVoxel = qov.PackedVoxel;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 7) {
        std.log.err("usage: {s} <svo_depth> <in_width> <in_height> <in_depth> in(.bvox) out(.svo)", .{
            if (args.len == 0) "svo_builder" else args[0],
        });
        return;
    }

    const depth: u6 = try std.fmt.parseInt(u6, args[1], 10);
    const dims: [3]usize = .{
        try std.fmt.parseInt(usize, args[2], 10),
        try std.fmt.parseInt(usize, args[3], 10),
        try std.fmt.parseInt(usize, args[4], 10),
    };

    const in_filename = args[5];
    const out_filename = args[6];

    const in_file = try std.fs.cwd().openFile(in_filename, .{});
    defer in_file.close();

    const mapped = try std.posix.mmap(null, blk: {
        const stat = try in_file.stat();
        const file_size = stat.size;
        const expected_size = dims[0] * dims[1] * dims[2] * @sizeOf(u32);
        std.debug.assert(file_size == expected_size);
        break :blk expected_size;
    }, std.posix.PROT.READ, .{
        .TYPE = .PRIVATE,
    }, in_file.handle, 0);
    defer std.posix.munmap(mapped);

    const out_file = try std.fs.cwd().createFile(out_filename, .{});
    defer out_file.close();

    const Context = struct {
        const Self = @This();

        in: [*]const PackedVoxel,
        dims: [3]usize,

        pub fn fun(
            ctx: Self,
            out_depth: u6,
            block_coords: [3]usize,
            out: [*]PackedVoxel,
        ) void {
            const sl = @as(usize, 1) << out_depth;
            const starting_coords = wgm.mulew(block_coords, sl);

            for (0..sl) |o_z| for (0..sl) |o_y| for (0..sl) |o_x| {
                const out_coords: [3]usize = .{ o_x, o_y, o_z };
                const ic = wgm.add(starting_coords, out_coords);

                if (ic[2] >= ctx.dims[2]) continue;
                if (ic[1] >= ctx.dims[1]) continue;
                if (ic[0] >= ctx.dims[0]) continue;

                const mat = ctx.in[ic[0] + (ic[1] + ic[2] * ctx.dims[1]) * ctx.dims[0]];
                out[o_x + (o_y + o_z * sl) * sl] = mat;
            };
        }
    };

    const context: Context = .{
        .in = @ptrCast(mapped),
        .dims = dims,
    };

    var finish_ctx: struct {
        const FContext = @This();

        out_file: std.fs.File,

        pub fn preempt_size(ctx: *FContext, words: usize) !void {
            _ = ctx;
            _ = words;
        }

        pub fn append_word(ctx: *FContext, word: u32) !void {
            try ctx.out_file.writeAll(std.mem.asBytes(&word));
        }

        pub fn append_words(ctx: *FContext, words: []const u32) !void {
            try ctx.out_file.writeAll(std.mem.sliceAsBytes(words));
        }
    } = .{
        .out_file = out_file,
    };

    try svo.create_svo_context(depth, 4, alloc, context, Context.fun, &finish_ctx);
}
