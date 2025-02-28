const std = @import("std");

const qoi = @import("qoi");
const wgm = @import("wgm");

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const VoxelProvider = @import("../VoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

const Provider = struct {
    pub fn init(self: *Self) VoxelProvider {
        return .{
            .provider = @ptrCast(self),

            .should_draw = Provider.should_draw,
            .should_redraw = VoxelProvider.never_draw,

            .draw = Provider.draw,
        };
    }

    pub fn should_draw(self: *anyopaque, range: [2][3]isize) bool {
        return @as(*Self, @ptrCast(@alignCast(self))).should_draw(range);
    }

    pub fn draw(self: *anyopaque, range: [2][3]isize, storage: []PackedVoxel) void {
        return @as(*Self, @ptrCast(@alignCast(self))).draw(range, storage);
    }
};

origin: [3]isize = .{ -3, 47, -3 },
image: qoi.Image,

pub fn from_file(filename: []const u8, depth: usize) !Self {
    const data = blk: {
        const cwd = std.fs.cwd();
        const file = try cwd.openFile(filename, .{
            .mode = .read_only,
        });

        const data = try file.readToEndAlloc(g.alloc, 256 * 1024 * 1024);

        break :blk data;
    };

    var image = try qoi.decode_image(data, g.alloc);
    image.depth = depth;
    image.height /= depth;

    defer g.alloc.free(data);

    return .{
        .image = image,
    };
}

pub fn deinit(self: Self) void {
    self.image.deinit();
}

pub fn to_provider(self: *Self) VoxelProvider {
    return Provider.init(self);
}

fn volume(self: Self) [2][3]isize {
    return .{
        self.origin,
        wgm.add(self.origin, wgm.cast(isize, [_]usize{
            self.image.width,
            self.image.height,
            self.image.depth,
        }).?),
    };
}

pub fn should_draw(self: Self, range: [2][3]isize) bool {
    const vol = self.volume();

    if (true) return false;
    return wgm.compare(.all, range[0], .greater_than_equal, vol[0]) //
    and wgm.compare(.all, range[0], .less_than, vol[1]) //
    and wgm.compare(.all, range[1], .greater_than_equal, vol[0]) //
    and wgm.compare(.all, range[1], .less_than, vol[1]);
}

pub fn draw(self: Self, range: [2][3]isize, storage: []PackedVoxel) void {
    const v = self.volume();

    const range_size = wgm.cast(usize, wgm.sub(range[1], range[0])).?;

    const overlapping_range: [2][3]isize = .{
        .{
            @max(range[0][0], v[0][0]),
            @max(range[0][1], v[0][1]),
            @max(range[0][2], v[0][2]),
        },
        .{
            @min(range[1][0], v[1][0]),
            @min(range[1][1], v[1][1]),
            @min(range[1][2], v[1][2]),
        },
    };

    const overlap_size = wgm.cast(usize, wgm.sub(overlapping_range[1], overlapping_range[0])) orelse return;

    const model_offset = wgm.cast(usize, wgm.sub(overlapping_range[0], self.origin)).?;
    const in_region_offset = wgm.cast(usize, wgm.sub(overlapping_range[0], range[0])).?;

    for (0..overlap_size[2]) |z| for (0..overlap_size[1]) |y| for (0..overlap_size[0]) |x| {
        const offset: [3]usize = .{ x, y, z };

        const ml_coords = wgm.add(model_offset, offset);
        const sample = self.image.data[ //
            ml_coords[2] * self.image.width * self.image.height //
            + ml_coords[1] * self.image.width //
            + ml_coords[0]
        ];

        const rl_coords = wgm.add(in_region_offset, offset);
        storage[
            rl_coords[2] * range_size[1] * range_size[0] //
            + rl_coords[1] * range_size[0] //
            + rl_coords[0]
        ] = .{
            .r = sample[0],
            .g = sample[1],
            .b = sample[2],
            .i = sample[3],
        };
    };
}
