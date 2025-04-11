const std = @import("std");

const dyn = @import("dyn");
const qov = @import("qov");
const wgm = @import("wgm");

const IThing = @import("../IThing.zig");
const IVoxelProvider = @import("../IVoxelProvider.zig");

const PackedVoxel = qov.PackedVoxel;
const Voxel = qov.Voxel;

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IVoxelProvider });

dims: [3]usize,
file: std.fs.File,

pub fn init(filename: []const u8, dims: [3]usize) !Self {
    const file = try std.fs.cwd().openFile(filename, .{});

    return .{
        .dims = dims,
        .file = file,
    };
}

pub fn draw_voxels(self: *Self, range: IVoxelProvider.VoxelRange, storage: []PackedVoxel) void {
    const info = IVoxelProvider.overlap_info(range, .{
        .origin = .{0} ** 3,
        .volume = self.dims,
    }) orelse return;

    for (0..info.volume[2]) |z| for (0..info.volume[1]) |y| {
        const words_to_read = info.volume[0];

        const offset = [_]usize{ 0, y, z };

        const ml_coords = wgm.add(info.local_origin, offset);
        const ml_idx = wgm.to_idx(ml_coords, self.dims);

        const sl_coords = wgm.add(
            wgm.cast(usize, wgm.sub(info.global_origin, range.origin)).?,
            offset,
        );
        const sl_idx = wgm.to_idx(sl_coords, range.volume);

        self.file.seekTo(ml_idx * 4) catch unreachable;
        const output_to = storage[sl_idx .. sl_idx + words_to_read];
        const read_bytes = self.file.readAll(std.mem.sliceAsBytes(output_to)) catch unreachable;
        _ = read_bytes;
        //if (read_bytes != words_to_read * 4) unreachable;
    };
}
