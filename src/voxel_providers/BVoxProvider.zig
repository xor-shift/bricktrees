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

const use_mmap = true;

dims: [3]usize,

mutex: std.Thread.Mutex = .{},
file: std.fs.File,

mapped: []align(std.mem.page_size) const u8,

pub fn init(filename: []const u8, dims: [3]usize) !Self {
    const file = try std.fs.cwd().openFile(filename, .{});

    const mapped_bytes: []align(std.mem.page_size) const u8 = if (use_mmap) try std.posix.mmap(
        null,
        dims[2] * dims[1] * dims[0] * 4,
        std.posix.PROT.READ,
        std.posix.system.MAP{ .TYPE = .PRIVATE, .ANONYMOUS = false },
        file.handle,
        0,
    ) else &.{};
    std.log.debug("{d}", .{mapped_bytes.len});

    return .{
        .dims = dims,
        .file = file,
        .mapped = mapped_bytes,
    };
}

pub fn deinit(self: *Self) void {
    if (use_mmap) std.posix.munmap(self.mapped);
    self.file.close();
}

pub fn draw_voxels(self: *Self, range: IVoxelProvider.VoxelRange, storage: []PackedVoxel) void {
    const info = IVoxelProvider.overlap_info(range, .{
        .origin = .{64} ** 3,
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

        const output_to = storage[sl_idx .. sl_idx + words_to_read];

        if (use_mmap) {
            @memcpy(
                std.mem.sliceAsBytes(output_to),
                self.mapped[ml_idx * 4 .. (ml_idx + words_to_read) * 4],
            );
        } else {
            self.mutex.lock();
            defer self.mutex.unlock();

            self.file.seekTo(ml_idx * 4) catch unreachable;
            const read_bytes = self.file.readAll(std.mem.sliceAsBytes(output_to)) catch unreachable;
            _ = read_bytes;
        }
    };
}
