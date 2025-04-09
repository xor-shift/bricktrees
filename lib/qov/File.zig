const std = @import("std");

const wgm = @import("wgm");

const qov = @import("root.zig");

const util = @import("util.zig");

const PackedVoxel = qov.PackedVoxel;
const Voxel = qov.Voxel;

const Self = @This();

pub const k_segment_size = [_]usize{ 64, 64, 64 };

const CompressionType = enum {
    RLE,
};

const SegmentData = union(enum) {
    LazyDeleted: void,
    Uncompressed: struct {
        data: []PackedVoxel,
    },

    fn deinit(self: SegmentData, alloc: std.mem.Allocator) void {
        switch (self) {
            .LazyDeleted => {},
            .Uncompressed => |v| alloc.free(v.data),
        }
    }
};

const Segment = struct {
    ml_s_coords: [3]usize,
    data: SegmentData,
};

alloc: std.mem.Allocator,
segments: std.ArrayList(Segment),

grid_dims: [3]usize = .{0} ** 3,
grid: []?usize = &.{}, // memoisation, won't be stored on the file

have_garbage: bool = false,

scratch_segment: []PackedVoxel,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{
        .alloc = alloc,

        .segments = std.ArrayList(Segment).init(alloc),

        .scratch_segment = try alloc.alloc(PackedVoxel, k_segment_size[2] * k_segment_size[1] * k_segment_size[0]),
    };
}

pub fn deinit(self: Self) void {
    self.alloc.free(self.grid);
    self.alloc.free(self.scratch_segment);

    for (self.segments.items) |segment| segment.data.deinit(self.alloc);
    self.segments.deinit();
}

pub fn ensure_grid_contains(self: *Self, ml_vox_coords: [3]usize) !void {
    const dims = wgm.divide_round_up(ml_vox_coords, k_segment_size);
    try self.ensure_grid_size(dims);
}

pub fn ensure_grid_size(self: *Self, grid_dims: [3]usize) !void {
    const actual = wgm.max(grid_dims, self.grid_dims);

    if (wgm.compare(.all, actual, .equal, self.grid_dims)) {
        return;
    }

    const old_grid = self.grid;
    self.grid = try util.resize_grid(
        ?usize,
        null,
        self.grid,
        self.grid_dims,
        actual,
        self.alloc,
    );
    self.alloc.free(old_grid);
    self.grid_dims = actual;
}

pub fn get_segment(self: Self, ml_s_coords: [3]usize) ?usize {
    if (wgm.compare(.some, ml_s_coords, .greater_than_equal, self.grid_dims)) return null;

    const idx = wgm.to_idx(ml_s_coords, self.grid_dims);
    return self.grid[idx];
}

/// This action is lazy. Call `collect_garbage` after removing segments.
pub fn remove_segment(self: *Self, ml_s_coords: [3]usize) void {
    const grid_idx = wgm.to_idx(ml_s_coords, self.grid_dims);
    const segment_idx = self.grid[grid_idx].?;

    self.have_garbage = true;

    self.segments.items[segment_idx].data.deinit(self.alloc);
    self.segments.items[segment_idx].data = .{ .LazyDeleted = {} };

    self.grid[grid_idx] = null;
}

pub fn collect_garbage(self: *Self) void {
    if (!self.have_garbage) return;

    // const segments_to_delete = blk: {
    //     var ret: usize = 0;
    //     for (self.segments) |segment| {
    //         if (segment.deleted) ret += 1;
    //     }
    //     break :blk ret;
    // };

    // const new_segments = try self.alloc.alloc(Segment, self.segments.len - segments_to_delete);
}

pub fn create_segment(
    self: *Self,
    ml_s_coords: [3]usize,
    clear_value: ?PackedVoxel,
) !usize {
    try self.ensure_grid_size(wgm.add(ml_s_coords, [_]usize{ 1, 1, 1 }));

    const ret = self.segments.items.len;
    try self.segments.append(Segment{
        .data = undefined,
        .ml_s_coords = ml_s_coords,
    });
    errdefer self.segments.shrinkRetainingCapacity(ret);

    const data = try self.alloc.alloc(PackedVoxel, k_segment_size[2] * k_segment_size[1] * k_segment_size[0]);
    errdefer self.alloc.free(data);
    if (clear_value) |v| @memset(data, v);

    self.segments.items[self.segments.items.len - 1].data = .{ .Uncompressed = .{
        .data = data,
    } };
    self.grid[wgm.to_idx(ml_s_coords, self.grid_dims)] = ret;

    return ret;
}

pub fn get_or_create_segment(
    self: *Self,
    ml_s_coords: [3]usize,
    clear_value: ?PackedVoxel,
) !usize {
    if (self.get_segment(ml_s_coords)) |v| return v;
    return try self.create_segment(ml_s_coords, clear_value);
}

/// /// Prefer get_region* wherever possible.
/// Prefer get_region* wherever possible
pub fn get_voxel(self: Self, ml_vox_coords: [3]usize) PackedVoxel {
    const s_coords = wgm.div(ml_vox_coords, k_segment_size);
    if (wgm.compare(.some, s_coords, .greater_than_equal, self.grid_dims)) return PackedVoxel.air;
    const s_index = self.grid[wgm.to_idx(s_coords, self.grid_dims)] orelse return PackedVoxel.air;

    const segment_data = switch (self.segments.items[s_index].data) {
        .LazyDeleted => return PackedVoxel.air,
        .Uncompressed => |v| v.data,
    };
    const sl_vox_coords = wgm.sub(ml_vox_coords, wgm.mulew(s_coords, k_segment_size));

    return segment_data[wgm.to_idx(sl_vox_coords, k_segment_size)];
}

const IteratorMode = union(enum) {
    constant,
    modifiable,
    create_new,

    pub fn const_self(self: IteratorMode) bool {
        return switch (self) {
            .constant => true,
            .modifiable => false,
            .create_new => false,
        };
    }
};

pub fn Iterator(comptime mode: IteratorMode) type {
    return struct {
        const SelfType = if (mode.const_self()) *const Self else *Self;
        const Iter = @This();

        pub const Result = struct {
            const BaseDataType = if (mode.const_self()) []const PackedVoxel else []PackedVoxel;
            const DataType = if (mode == .create_new) BaseDataType else ?BaseDataType;

            segment_data: DataType,

            offset_into_segment: [3]usize,
            offset_into_region: [3]usize,

            segment_dims: [3]usize,
            absolute_segment_dims: [3]usize = k_segment_size,
        };

        self: SelfType,

        clear_value: ?PackedVoxel = null,

        vox_coords: [3]usize,
        vox_dims: [3]usize,

        start_segment: [3]usize,
        segment_dims: [3]usize,

        current: usize = 0,

        fn init(self: SelfType, vox_coords: [3]usize, vox_dims: [3]usize, clear_value: ?PackedVoxel) Iter {
            const start_segment = wgm.div(vox_coords, k_segment_size);
            const end_segment = wgm.divide_round_up(wgm.add(vox_coords, vox_dims), k_segment_size);
            const segment_dims = wgm.sub(end_segment, start_segment);

            return .{
                .self = self,

                .clear_value = clear_value,

                .vox_coords = vox_coords,
                .vox_dims = vox_dims,

                .start_segment = start_segment,
                .segment_dims = segment_dims,
            };
        }

        pub fn next(iter: *Iter) if (mode == .create_new) anyerror!?Result else ?Result {
            if (iter.current >= iter.segment_dims[2] * iter.segment_dims[1] * iter.segment_dims[0]) {
                return null;
            }

            const cur_segment_coords = wgm.add(wgm.from_idx(iter.current, iter.segment_dims), iter.start_segment);
            iter.current += 1;

            const ideal_segment_origin = wgm.mulew(cur_segment_coords, k_segment_size);
            const actual_extents: [2][3]usize = .{
                wgm.max(ideal_segment_origin, iter.vox_coords),
                wgm.min(wgm.add(ideal_segment_origin, k_segment_size), wgm.add(iter.vox_coords, iter.vox_dims)),
            };

            const segment_offset = wgm.sub(actual_extents[0], ideal_segment_origin);
            const region_offset = wgm.sub(actual_extents[0], iter.vox_coords);

            switch (mode) {
                .create_new => {
                    const idx = try iter.self.get_or_create_segment(cur_segment_coords, iter.clear_value);
                    return Result{
                        .segment_data = iter.self.segments.items[idx].data.Uncompressed.data,

                        .offset_into_segment = segment_offset,
                        .offset_into_region = region_offset,

                        .segment_dims = wgm.sub(actual_extents[1], actual_extents[0]),
                    };
                },
                else => {
                    const maybe_idx = iter.self.get_segment(cur_segment_coords);
                    return Result{
                        .segment_data = if (maybe_idx) |idx| iter.self.segments.items[idx].data.Uncompressed.data else null,

                        .offset_into_segment = segment_offset,
                        .offset_into_region = region_offset,

                        .segment_dims = wgm.sub(actual_extents[1], actual_extents[0]),
                    };
                },
            }
        }
    };
}

pub fn iterator_readonly(self: *const Self, vox_coords: [3]usize, vox_dims: [3]usize) Iterator(.constant) {
    return Iterator(.constant).init(self, vox_coords, vox_dims, null);
}

pub fn iterator_modifiable(self: *Self, vox_coords: [3]usize, vox_dims: [3]usize) Iterator(.modifiable) {
    return Iterator(.modifiable).init(self, vox_coords, vox_dims, null);
}

pub fn iterator_create_new(self: *Self, vox_coords: [3]usize, vox_dims: [3]usize, clear_value: ?PackedVoxel) Iterator(.create_new) {
    return Iterator(.create_new).init(self, vox_coords, vox_dims, clear_value);
}

pub fn fill_region(self: *Self, vox_coords: [3]usize, vox_dims: [3]usize, value: PackedVoxel) !void {
    var iterator = self.iterator_create_new(vox_coords, vox_dims, PackedVoxel.air);
    while (try iterator.next()) |res| {
        const len = res.segment_dims[0];

        for (0..res.segment_dims[2]) |sl_z| for (0..res.segment_dims[1]) |sl_y| {
            const out_start = wgm.to_idx(
                wgm.add([_]usize{ 0, sl_y, sl_z }, res.offset_into_segment),
                k_segment_size,
            );

            @memset(res.segment_data[out_start .. out_start + len], value);
        };
    }
}

pub fn set_region(self: *Self, vox_coords: [3]usize, vox_dims: [3]usize, in: []const PackedVoxel) !void {
    var iterator = self.iterator_create_new(vox_coords, vox_dims, PackedVoxel.air);
    while (try iterator.next()) |res| {
        const len = res.segment_dims[0];

        for (0..res.segment_dims[2]) |sl_z| for (0..res.segment_dims[1]) |sl_y| {
            const out_start = wgm.to_idx(
                wgm.add([_]usize{ 0, sl_y, sl_z }, res.offset_into_segment),
                res.absolute_segment_dims,
            );

            const in_start = wgm.to_idx(
                wgm.add([_]usize{ 0, sl_y, sl_z }, res.offset_into_region),
                vox_dims,
            );

            @memcpy(
                res.segment_data[out_start .. out_start + len],
                in[in_start .. in_start + len],
            );
        };
    }
}

pub fn get_region_inplace(self: Self, vox_coords: [3]usize, vox_dims: [3]usize, out: []PackedVoxel) !void {
    var iterator = self.iterator_readonly(vox_coords, vox_dims);
    while (iterator.next()) |res| {
        const len = res.segment_dims[0];

        for (0..res.segment_dims[2]) |sl_z| for (0..res.segment_dims[1]) |sl_y| {
            const out_start = wgm.to_idx(
                wgm.add([_]usize{ 0, sl_y, sl_z }, res.offset_into_segment),
                k_segment_size,
            );

            const in_start = wgm.to_idx(
                wgm.add([_]usize{ 0, sl_y, sl_z }, res.offset_into_region),
                vox_dims,
            );

            if (res.segment_data) |data| {
                @memcpy(
                    out[in_start .. in_start + len],
                    data[out_start .. out_start + len],
                );
            } else {
                @memset(
                    out[in_start .. in_start + len],
                    PackedVoxel.air,
                );
            }
        };
    }
}

test "iterators" {
    const alloc = std.testing.allocator;

    var file = try Self.init(alloc);
    defer file.deinit();

    //          1   64  1
    //        +---+---+---+ <- 192, 193, 193
    //     1 / 1 / 3 / 5 /| 63
    //      +---+---+---+ +
    //  64 / 0 / 2 / 4 /|/ 1
    //    +---+---+---+ +          x y
    // 63 |   |   |   |/ 64        |/
    //    +---+---+---+            *-z
    //    ^ 1   64  1
    //    129, 128, 127
    var iter = file.iterator_create_new(.{ 129, 128, 127 }, .{ 63, 65, 66 }, PackedVoxel.air);

    while (try iter.next()) |res| {
        const ml_origin = wgm.add([_]usize{ 129, 128, 127 }, res.offset_into_region);

        // eyeball debugging FTW
        std.log.debug("{any}..{any} <- {any}..{any} ({any}, @{any}) ", .{
            res.offset_into_region,
            wgm.add(res.offset_into_region, res.segment_dims),
            ml_origin,
            wgm.add(ml_origin, res.segment_dims),
            res.segment_dims,
            res.segment_data.ptr,
        });
    }
}

test "(get|set|fill)_region" {
    const alloc = std.testing.allocator;

    const dims = [_]usize{ 255, 254, 253 };
    const raw_data = try alloc.alloc(PackedVoxel, dims[0] * dims[1] * dims[2]);
    @memset(raw_data, PackedVoxel.white);
    defer alloc.free(raw_data);

    var file = try Self.init(alloc);
    defer file.deinit();

    try file.set_region(.{0} ** 3, dims, raw_data);

    try std.testing.expectEqual(64, file.segments.items.len);
    for (0..27) |compact_s_coords| {
        const s_coords = wgm.from_idx(compact_s_coords, [_]usize{3} ** 3);
        const segment_data = file.segments.items[file.grid[wgm.to_idx(s_coords, file.grid_dims)].?].data.Uncompressed.data;

        const res = std.mem.indexOfNone(
            u32,
            @ptrCast(segment_data),
            &.{@bitCast(PackedVoxel.white)},
        );

        try std.testing.expectEqual(null, res);
    }

    try std.testing.expectEqual(PackedVoxel.air, file.get_voxel(.{ 256, 256, 256 }));
    try std.testing.expectEqual(PackedVoxel.air, file.get_voxel(.{ 255, 254, 253 }));
    try std.testing.expectEqual(PackedVoxel.white, file.get_voxel(.{ 254, 253, 252 }));

    const out = try alloc.alloc(PackedVoxel, 36);
    defer alloc.free(out);

    const a = PackedVoxel.air;
    const w = PackedVoxel.white;
    const r: PackedVoxel = .{ .r = 255, .g = 0, .b = 0, .i = 255 };

    try file.get_region_inplace(.{252} ** 3, .{ 4, 3, 3 }, out);
    try std.testing.expectEqualSlices(PackedVoxel, &.{
        w, w, w, a,
        w, w, w, a,
        a, a, a, a,

        a, a, a, a,
        a, a, a, a,
        a, a, a, a,

        a, a, a, a,
        a, a, a, a,
        a, a, a, a,
    }, out);

    try file.fill_region(.{ 253, 253, 252 }, .{ 2, 1, 2 }, r);

    try file.get_region_inplace(.{252} ** 3, .{ 4, 3, 3 }, out);
    try std.testing.expectEqualSlices(PackedVoxel, &.{
        w, w, w, a,
        w, r, r, a,
        a, a, a, a,

        a, a, a, a,
        a, r, r, a,
        a, a, a, a,

        a, a, a, a,
        a, a, a, a,
        a, a, a, a,
    }, out);
}

test {
    std.testing.refAllDecls(util);
}

pub fn encode(self: Self, writer: std.io.AnyWriter) !usize {
    return @import("encoder/v1.zig").encode(self, writer);
}

test encode {
    const cwd = std.fs.cwd();
    const out_file = try cwd.createFile("out.qov", .{});
    defer out_file.close();
    const writer = out_file.writer();

    const alloc = std.testing.allocator;
    var file = try Self.init(alloc);
    defer file.deinit();
    try file.fill_region(.{ 63, 62, 61 }, .{ 2, 3, 4 }, PackedVoxel.white);

    {
        var rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64));
        var iter = file.iterator_create_new(.{128} ** 3, .{64} ** 3, null);
        while (try iter.next()) |res| {
            for (0..res.segment_data.len) |i| {
                const v: u32 = @truncate(rand.next());
                res.segment_data[i] = @bitCast(v);
            }
        }
    }

    _ = try file.encode(writer.any());
}

pub fn decode(reader: std.io.AnyReader, alloc: std.mem.Allocator) !Self {
    return @import("decoder/v1.zig").decode(reader, alloc);
}

test decode {
    const alloc = std.testing.allocator;

    var storage = std.ArrayList(u8).init(alloc);
    defer storage.deinit();

    var file = try Self.init(alloc);
    defer file.deinit();
    try file.fill_region(.{ 63, 62, 61 }, .{ 2, 3, 4 }, PackedVoxel.white);

    {
        var rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64));
        var iter = file.iterator_create_new(.{128} ** 3, .{64} ** 3, null);
        while (try iter.next()) |res| {
            for (0..res.segment_data.len) |i| {
                const v: u32 = @truncate(rand.next());
                res.segment_data[i] = @bitCast(v);
            }
        }
    }

    _ = try file.encode(storage.writer().any());

    const Context = struct {
        list: std.ArrayList(u8),
        ptr: usize = 0,
    };

    var _ctx: Context = .{ .list = storage };

    const decoded = try Self.decode((std.io.Reader(
        *Context,
        error{},
        struct {
            pub fn aufruf(ctx: *Context, buffer: []u8) error{}!usize {
                const remaining = ctx.list.items.len - ctx.ptr;
                const len_to_read = @min(buffer.len, remaining);
                @memcpy(buffer, ctx.list.items[ctx.ptr .. ctx.ptr + len_to_read]);
                ctx.ptr += len_to_read;
                return len_to_read;
            }
        }.aufruf,
    ){ .context = &_ctx }).any(), alloc);
    // std.log.debug("{any}", .{decoded});

    defer decoded.deinit();
}
