const std = @import("std");

const blas = @import("../blas/blas.zig");

const util = @import("util.zig");

pub const RenderBlock = packed struct(u32) {
    block_id: u22,
    block_state: u10,
};

const Self = @This();

const LocalCoord = blas.Vec3uz;

mips_stale: bool = false,
mips: *[util.u8_mip_size / 8]u8, // as granular as it gets
blocks: *[64][64][64]RenderBlock,

pub fn init(alloc: std.mem.Allocator) !Self {
    const mips = try alloc.create([util.u8_mip_size / 8]u8);
    errdefer alloc.destroy(mips);

    const blocks = try alloc.create([64][64][64]RenderBlock);
    errdefer alloc.destroy(blocks);

    var ret: Self = .{
        .mips = mips,
        .blocks = blocks,
    };

    @memset(mips.*[0..], 0);
    @memset(ret.flat_blocks_slice(), @bitCast(@as(u32, 0)));

    return ret;
}

pub fn flat_blocks(self: Self) *[64 * 64 * 64]RenderBlock {
    return @ptrCast(self.blocks);
}

pub fn flat_blocks_slice(self: Self) []RenderBlock {
    return self.flat_blocks().*[0..];
}

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self.blocks);
    alloc.destroy(self.mips);
}

/// Set `lazy_mips` to false if this is a one-off change.
/// Set it to true if you are filling an area for instance (mass-setting mips
/// is fairly efficient).
pub fn set(self: *Self, coord: LocalCoord, block: RenderBlock, lazy_mips: bool) void {
    std.debug.assert(blas.all(blas.less_than(coord, blas.vec3uz(64, 64, 64))));

    self.blocks[coord.z()][coord.y()][coord.x()] = block;

    if (lazy_mips or self.mips_stale) {
        self.mips_stale = true;
        return;
    }

    for (util.u8_mipmap_indices(coord)) |level_offset| {
        const byte_offset = level_offset / 8;
        const bit_offset = @as(u3, @intCast(level_offset % 8));

        // std.log.debug("setting byte {d}, bit {d}", .{ byte_offset, bit_offset });

        self.mips[byte_offset] |= @as(u8, 1) << bit_offset;
    }
}

/// Defo call this before uploading to the GPU. No work will be done if the
/// mips are OK.
pub fn generate_mips(self: *Self) void {
    if (!self.mips_stale) return;

    @memset(self.mips.*[0..], 255);
}

test "chunk no leak" {
    //
}
