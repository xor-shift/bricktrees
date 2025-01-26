const std = @import("std");

const blas = @import("blas");
const wgpu = @import("gfx").wgpu;

pub const Brickmap = @import("../../brick/map.zig").U8Map(5);

const Self = @This();

const brickmap_texture_desc = wgpu.Texture.Descriptor{
    .label = "some brickmap texture",
    .size = .{
        .width = Brickmap.Traits.side_length,
        .height = Brickmap.Traits.side_length,
        .depth_or_array_layers = Brickmap.Traits.side_length,
    },
    .usage = .{
        .copy_dst = true,
        .texture_binding = true,
    },
    .format = .RGBA8Uint,
    .dimension = .D3,
    .sampleCount = 1,
    .mipLevelCount = 1,
    .view_formats = &.{},
};

const bricktree_buffer_desc = wgpu.Buffer.Descriptor{
    .label = "some bricktree texture",
    .size = (Brickmap.Traits.no_tree_bits / 8 + 3) / 4 * 4,
    .usage = .{
        .copy_dst = true,
        .storage = true,
    },
    .mapped_at_creation = false,
};

pub const BrickmapInfo = struct {
    pub const State = enum {
        Junk,
        UploadToGPU,
        DownloadFromGPU,
        Valid,
    };

    state: State,
    brickmap_coords: blas.Vec3uz,
};

pub const BrickgridEntry = struct {
    brickmap: usize,
};

pub const MapConfig = struct {
    no_brickmaps: usize,
    grid_dimensions: [3]usize,

    pub fn grid_size(self: MapConfig) usize {
        return 1 *
            self.grid_dimensions[0] *
            self.grid_dimensions[1] *
            self.grid_dimensions[2];
    }
};

config: MapConfig,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
brickgrid_texture: wgpu.Texture,
brickgrid_texture_view: wgpu.TextureView,

alloc: std.mem.Allocator,

brickgrid_synced: bool = false,
local_brickgrid: [*]?BrickgridEntry,

local_brickmaps: [*]BrickmapInfo,
bricktree_buffers: [*]wgpu.Buffer,
brickmap_textures: [*]wgpu.Texture,
brickmap_texture_views: [*]wgpu.TextureView,

pub fn init(alloc: std.mem.Allocator, device: wgpu.Device, config: MapConfig) !Self {
    var successful_initialisations: usize = 0;

    const local_brickgrid = try alloc.alloc(
        ?BrickgridEntry,
        1 *
            config.grid_dimensions[0] *
            config.grid_dimensions[1] *
            config.grid_dimensions[2],
    );
    errdefer alloc.free(local_brickgrid);

    @memset(local_brickgrid, null);

    const local_brickmaps = try alloc.alloc(BrickmapInfo, config.no_brickmaps);
    errdefer alloc.free(local_brickmaps);

    const bricktree_buffers = try alloc.alloc(wgpu.Buffer, config.no_brickmaps);
    errdefer alloc.free(bricktree_buffers);
    errdefer for (0..successful_initialisations) |i| bricktree_buffers[i].deinit();

    const brickmap_textures = try alloc.alloc(wgpu.Texture, config.no_brickmaps);
    errdefer alloc.free(brickmap_textures);
    errdefer for (0..successful_initialisations) |i| brickmap_textures[i].deinit();

    const brickmap_texture_views = try alloc.alloc(wgpu.TextureView, config.no_brickmaps);
    errdefer alloc.free(brickmap_texture_views);
    errdefer for (0..successful_initialisations) |i| brickmap_texture_views[i].deinit();

    const brickgrid_texture = try device.create_texture(wgpu.Texture.Descriptor{
        .label = "brickgrid texture",
        .size = .{
            .width = @intCast(config.grid_dimensions[0]),
            .height = @intCast(config.grid_dimensions[1]),
            .depth_or_array_layers = @intCast(config.grid_dimensions[2]),
        },
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .format = .R32Uint,
        .dimension = .D3,
        .sampleCount = 1,
        .mipLevelCount = 1,
        .view_formats = &.{},
    });
    errdefer brickgrid_texture.deinit();

    const brickgrid_texture_view = try brickgrid_texture.create_view(null);
    errdefer brickgrid_texture_view.deinit();

    for (0..config.no_brickmaps) |i| {
        const bricktree_buffer = try device.create_buffer(bricktree_buffer_desc);
        errdefer bricktree_buffer.deinit();

        const brickmap_texture = try device.create_texture(brickmap_texture_desc);
        errdefer brickmap_texture.deinit();

        const brickmap_texture_view = try brickgrid_texture.create_view(null);
        errdefer brickmap_texture_view.deinit();

        bricktree_buffers[i] = bricktree_buffer;
        brickmap_textures[i] = brickmap_texture;
        brickmap_texture_views[i] = brickmap_texture_view;

        successful_initialisations += 1;
    }

    const map_bgl = try device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
        .label = "map bgl",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .compute = true },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D3,
                } },
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 1,
                .visibility = .{ .compute = true },
                .layout = .{ .Buffer = .{
                    .type = .ReadOnlyStorage,
                    .min_binding_size = Brickmap.Traits.no_tree_bits / 8,
                } },
                .count = config.no_brickmaps,
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 2,
                .visibility = .{ .compute = true },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D3,
                } },
                .count = config.no_brickmaps,
            },
        },
    });
    errdefer map_bgl.deinit();

    const map_bg = try device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "grid bg",
        .layout = map_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .TextureView = brickgrid_texture_view },
            },
            wgpu.BindGroup.Entry{
                .binding = 1,
                .resource = .{ .BufferArray = bricktree_buffers },
            },
            wgpu.BindGroup.Entry{
                .binding = 2,
                .resource = .{ .TextureViewArray = brickmap_texture_views },
            },
        },
    });
    errdefer map_bg.deinit();

    return .{
        .config = config,

        .map_bgl = map_bgl,
        .map_bg = map_bg,
        .brickgrid_texture = brickgrid_texture,
        .brickgrid_texture_view = brickgrid_texture_view,

        .alloc = alloc,

        .local_brickgrid = local_brickgrid.ptr,

        .local_brickmaps = local_brickmaps.ptr,
        .bricktree_buffers = bricktree_buffers.ptr,
        .brickmap_textures = brickmap_textures.ptr,
        .brickmap_texture_views = brickmap_texture_views.ptr,
    };
}

pub fn deinit(self: *Self) void {
    const bricktree_buffers = self.bricktree_buffers[0..self.config.no_brickmaps];
    const brickmap_textures = self.brickmap_textures[0..self.config.no_brickmaps];
    const brickmap_texture_views = self.brickmap_texture_views[0..self.config.no_brickmaps];

    for (brickmap_texture_views) |v| v.deinit();
    self.alloc.free(brickmap_texture_views);

    for (brickmap_textures) |v| v.deinit();
    self.alloc.free(brickmap_textures);

    for (bricktree_buffers) |v| v.deinit();
    self.alloc.free(bricktree_buffers);

    self.brickgrid_texture.deinit();

    self.alloc.free(self.local_brickgrid[0..self.config.grid_size()]);
    self.alloc.free(self.local_brickmaps[0..self.config.no_brickmaps]);

    self.map_bg.deinit();
    self.map_bgl.deinit();
}

/// Call this before doing anything in render().
pub fn before_render(self: *Self) void {
    _ = self;
}
