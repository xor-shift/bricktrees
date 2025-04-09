const std = @import("std");

const wgm = @import("wgm");

const voxel = @import("../voxel.zig");

const File = @import("../File.zig");

const PackedVoxel = voxel.PackedVoxel;

fn decide_segment_type(segment: []const PackedVoxel) SegmentType {
    // TODO: this decision can be made better

    const seed = std.crypto.random.int(u64);
    var rng = std.Random.Xoshiro256.init(seed);
    const rand = rng.random();

    const check_ct: usize = 8;
    const check_sz: usize = 64;

    var total_unique: usize = 0;
    for (0..check_ct) |_| {
        const start = rand.intRangeAtMost(usize, 0, segment.len - check_sz);

        var local_unique: usize = 0;
        var storage = [_]PackedVoxel{undefined} ** check_sz;
        for (0..check_sz) |i| {
            const encountered = storage[0..local_unique];
            const v = segment[start + i];
            if (std.mem.indexOfScalar(u32, @ptrCast(encountered), @bitCast(v)) != null) {
                continue;
            }

            storage[local_unique] = v;
            local_unique += 1;
        }

        total_unique += local_unique;
    }

    const average_unique = total_unique / check_ct;

    if (average_unique <= 4) return SegmentType.rle;
    if (average_unique <= 48) return SegmentType.qoi;
    return SegmentType.raw;
}

fn encode_segment_raw(segment: []const PackedVoxel, writer: std.io.AnyWriter) !usize {
    const as_u32: []const u32 = @ptrCast(segment);

    try writer.writeAll(std.mem.sliceAsBytes(as_u32));

    return segment.len * @sizeOf(u32);
}

fn encode_segment_rle(segment: []const PackedVoxel, writer: std.io.AnyWriter) !usize {
    var written: usize = 0;

    const as_u32: []const u32 = @ptrCast(segment);

    var last: u32 = @bitCast(PackedVoxel.air);
    var offset: usize = 0;

    while (offset != segment.len) {
        const remaining = as_u32[offset..];
        const run_length = blk: {
            for (remaining, 0..) |v, i| if (v != last) break :blk i;
            break :blk remaining.len;
        };

        if (run_length == 0) {
            last = remaining[0];

            try writer.writeInt(u16, 0, .little);
            written += @sizeOf(u16);
            try writer.writeInt(u32, last, .little);
            written += @sizeOf(u32);

            offset += 1;
            continue;
        }

        const actual_run_length = @min(65535, run_length);

        try writer.writeInt(u16, @intCast(actual_run_length), .little);
        written += @sizeOf(u16);
        offset += actual_run_length;
    }

    return written;
}

fn encode_segment_qoi(segment: []const PackedVoxel, writer: std.io.AnyWriter) !usize {
    // NYI
    return encode_segment_rle(segment, writer);
}

pub const SegmentType = enum(u8) {
    raw = 0,
    rle = 1,
    qoi = 2,
};

pub const CurveType = enum(u8) {
    raster = 0,
    morton = 1,
    hilbert = 2,
};

pub const Header = extern struct {
    magic: [4]u8,
    version: u32,
    num_segments: u32,
};

pub const SegmentHeader = extern struct {
    segment_coords: [3]u32,
    segment_type: SegmentType,
    curve_type: CurveType,
    padding: [2]u8 = undefined,
};

/// It is highly, HIGHLY advised to pass in a buffered writer here.
pub fn encode(file: File, writer: std.io.AnyWriter) !usize {
    var written: usize = 0;

    try writer.writeStruct(Header{
        .magic = .{ 'q', 'o', 'v', 'f' },
        .version = 1,
        .num_segments = blk: {
            var ret: u32 = 0;
            for (file.segments.items) |segment| {
                ret += switch (segment.data) {
                    .LazyDeleted => 0,
                    else => 1,
                };
            }
            break :blk ret;
        },
    });
    written += @sizeOf(Header);

    //const gd = file.grid_dims;
    for (file.segments.items) |segment| {
        const segment_data = switch (segment.data) {
            .LazyDeleted => continue,
            .Uncompressed => |v| v.data,
        };

        const segment_type = decide_segment_type(segment_data);

        try writer.writeStruct(SegmentHeader{
            .segment_coords = wgm.cast(u32, segment.ml_s_coords).?,
            .segment_type = segment_type,
            .curve_type = .raster,
        });
        written += @sizeOf(SegmentHeader);

        const segment_sz = switch (segment_type) {
            .rle => try encode_segment_rle(segment_data, writer),
            .qoi => @panic("NYI"),
            .raw => try encode_segment_raw(segment_data, writer),
        };
        written += segment_sz;

        // std.log.debug("wrote {d} bytes for the segment at {any} with the physical type {s}", .{
        //     segment_sz,
        //     s_coords,
        //     @tagName(segment_type),
        // });
    }

    return written;
}
