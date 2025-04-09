const std = @import("std");

const wgm = @import("wgm");

const encoder = @import("../encoder/v1.zig");
const voxel = @import("../voxel.zig");

const File = @import("../File.zig");

const PackedVoxel = voxel.PackedVoxel;

pub const DecodeError = error{
    bad_magic,
    unsupported_version,
    unsupported_feature,

    duplicate_segment,

    segment_runoff,
};

pub fn decode_raw(reader: std.io.AnyReader, segment: []PackedVoxel) !void {
    const as_u32: []u32 = @ptrCast(segment);
    try reader.readNoEof(std.mem.sliceAsBytes(as_u32));
}

pub fn decode_rle(reader: std.io.AnyReader, segment: []PackedVoxel) !void {
    var idx: usize = 0;
    var last = PackedVoxel.air;

    while (idx != segment.len) {
        const run_length: usize = @intCast(try reader.readInt(u16, .little));
        if (run_length == 0) {
            last = @bitCast(try reader.readInt(u32, .little));
            segment[idx] = last;
            idx += 1;
            continue;
        }

        if (idx + run_length > segment.len) {
            return DecodeError.segment_runoff;
        }

        @memset(segment[idx .. idx + run_length], last);
        idx += run_length;
    }
}

pub fn decode(reader: std.io.AnyReader, alloc: std.mem.Allocator) !File {
    const header = try reader.readStruct(encoder.Header);

    if (!std.meta.eql(header.magic, .{ 'q', 'o', 'v', 'f' })) {
        return DecodeError.bad_magic;
    }

    if (header.version != 1) {
        return DecodeError.unsupported_version;
    }

    var ret = try File.init(alloc);
    errdefer ret.deinit();

    for (0..header.num_segments) |_| {
        const segment_header = try reader.readStruct(encoder.SegmentHeader);

        const segment_coords = wgm.cast(usize, segment_header.segment_coords).?;
        try ret.ensure_grid_size(wgm.add(segment_coords, [_]usize{ 1, 1, 1 }));

        if (segment_header.curve_type != .raster) {
            return DecodeError.unsupported_feature;
        }

        if (ret.get_segment(segment_coords)) |_| {
            return DecodeError.duplicate_segment;
        }

        const segment_idx = try ret.create_segment(segment_coords, null);
        const segment_data = ret.segments.items[segment_idx].data.Uncompressed.data;

        switch (segment_header.segment_type) {
            .raw => try decode_raw(reader, segment_data),
            .rle => try decode_rle(reader, segment_data),
            .qoi => return DecodeError.unsupported_feature,
        }
    }

    return ret;
}
