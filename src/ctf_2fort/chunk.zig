const std = @import("std");

const blas = @import("../blas/blas.zig");
const wgpu = @import("../wgpu/wgpu.zig");

const material = @import("material.zig");
const util = @import("util.zig");

const g_state = &@import("../main.zig").g_state;

const Self = @This();

/// Chunk-local voxel coordinates
const LocalCoord = blas.Vec3uz;

/// Global voxel coordinates
const GlobalCoord = blas.Vec3uz;

/// ChunkCoord of (1, 2, 3) corresponds to a GlobalCoord of (64, 128, 192)
const ChunkCoord = blas.Vec3uz;

pub const Material = material.Material;

pub const SyncStatus = enum {
    Synced,
    UploadToGPU,
    DownloadFromGPU,
};

mips: *[util.u8_mip_size / 8]u8, // as granular as it gets
blocks: *[64][64][64]Material,

status: SyncStatus = .UploadToGPU,

tree_valid: bool = true,
tree_status: SyncStatus = .UploadToGPU,

chunk_texture: wgpu.Texture,
chunk_texture_view: wgpu.TextureView,
tree_texture: wgpu.Texture,
tree_texture_view: wgpu.TextureView,

pub fn init(alloc: std.mem.Allocator) !Self {
    const mips = try alloc.create([util.u8_mip_size / 8]u8);
    errdefer alloc.destroy(mips);

    const blocks = try alloc.create([64][64][64]Material);
    errdefer alloc.destroy(blocks);

    const chunk_texture = try g_state.device.create_texture(.{
        .label = "a chunk texture",
        .usage = .{
            .copy_src = true,
            .copy_dst = true,
            .texture_binding = true,
            .storage_binding = true,
        },
        .dimension = .D3,
        .size = .{
            .width = 64,
            .height = 64,
            .depth_or_array_layers = 64,
        },
        .format = .R32Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });
    errdefer chunk_texture.release();

    const tree_texture = try g_state.device.create_texture(.{
        .label = "a chunk's tree texture",
        .usage = .{
            .copy_src = true,
            .copy_dst = true,
            .texture_binding = true,
            .storage_binding = false,
        },
        .dimension = .D1,
        .size = .{
            .width = 64,
            .height = 1,
            .depth_or_array_layers = 1,
        },
        .format = .R8Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });
    errdefer tree_texture.release();

    const chunk_texture_view = try chunk_texture.create_view(null);
    errdefer chunk_texture_view.release();

    const tree_texture_view = try tree_texture.create_view(null);
    errdefer tree_texture_view.release();

    var ret: Self = .{
        .mips = mips,
        .blocks = blocks,
        .chunk_texture = chunk_texture,
        .chunk_texture_view = chunk_texture_view,
        .tree_texture = tree_texture,
        .tree_texture_view = tree_texture_view,
    };

    @memset(mips.*[0..], 0);
    @memset(ret.flat_blocks_slice(), @bitCast(@as(u32, 0)));

    return ret;
}

pub fn flat_blocks(self: Self) *[64 * 64 * 64]Material {
    return @ptrCast(self.blocks);
}

pub fn flat_blocks_slice(self: Self) []Material {
    return self.flat_blocks().*[0..];
}

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self.mips);
    alloc.destroy(self.blocks);

    self.chunk_texture.release();
    self.chunk_texture_view.release();
    self.tree_texture.release();
    self.tree_texture_view.release();
}

/// Set `lazy_mips` to false if this is a one-off change.
/// Set it to true if you are filling an area for instance (mass-setting mips
/// is fairly efficient).
pub fn set(self: *Self, coord: LocalCoord, block: Material, lazy_mips: bool) void {
    std.debug.assert(blas.all(blas.less_than(coord, blas.vec3uz(64, 64, 64))));

    self.blocks[coord.z()][coord.y()][coord.x()] = block;

    if (lazy_mips or !self.tree_valid) {
        self.tree_valid = false;
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
pub fn generate_tree(self: *Self) void {
    if (self.tree_valid) return;

    self.tree_valid = true;
    self.tree_status = .UploadToGPU;

    @memset(self.mips.*[0..], 255);
}

pub fn upload(self: *Self) void {
    if (!self.tree_valid) {
        self.generate_tree();
    }

    if (self.status == .Synced) {
        return;
    }
}
