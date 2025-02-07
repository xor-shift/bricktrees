const std = @import("std");

const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const brick = @import("../../brick.zig");

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const BrickmapCoordinates = brick.BrickmapCoordinates;
const VoxelCoordinates = brick.VoxelCoordinates;

const g = &@import("../../main.zig").g;

const Self = @This();

pub const Brickmap = brick.U8Map(5);

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
    .size = Brickmap.Traits.no_tree_bits / 8 - 1,
    .usage = .{
        .copy_dst = true,
        .storage = true,
    },
    .mapped_at_creation = false,
};

pub const BrickmapInfo = struct {
    /// This is true in ~~two~~ one situation~~s~~:
    /// - The data on the GPU is junk for this brickmap
    /// ~~- Another brickmap was uploaded to anoter slot at the same location.~~
    ///
    /// Both `valid` and `committed` can be `true` at the same time.
    valid: bool = false,

    /// Value is undefined if `!valid`.
    last_accessed: usize = undefined,

    /// Value is undefined if `!valid`.
    brickmap_coords: [3]usize = undefined,
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

const QueuedBrickmap = struct {
    brickmap: *Brickmap,
    coords: BrickmapCoordinates,
};

config: MapConfig,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
brickgrid_texture: wgpu.Texture,
brickgrid_texture_view: wgpu.TextureView,

bigass_mutex: std.Thread.Mutex = .{},

brickmap_queue: std.ArrayList(QueuedBrickmap),

alloc: std.mem.Allocator,

brickmap_tracker: [*]BrickmapInfo,
bricktree_buffers: [*]wgpu.Buffer,
brickmap_textures: [*]wgpu.Texture,
brickmap_texture_views: [*]wgpu.TextureView,

pub fn init(alloc: std.mem.Allocator, device: wgpu.Device, config: MapConfig) !Self {
    var successful_initialisations: usize = 0;

    const brickmap_tracker = try alloc.alloc(BrickmapInfo, config.no_brickmaps);
    errdefer alloc.free(brickmap_tracker);
    @memset(brickmap_tracker, .{});

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
                    .min_binding_size = Brickmap.Traits.no_tree_bits / 8 - 1,
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

    const brickmap_queue = std.ArrayList(QueuedBrickmap).init(g.biframe_alloc);

    return .{
        .config = config,

        .map_bgl = map_bgl,
        .map_bg = map_bg,
        .brickgrid_texture = brickgrid_texture,
        .brickgrid_texture_view = brickgrid_texture_view,

        .brickmap_queue = brickmap_queue,

        .alloc = alloc,

        .brickmap_tracker = brickmap_tracker.ptr,
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

    self.alloc.free(self.brickmap_tracker[0..self.config.no_brickmaps]);

    self.map_bg.deinit();
    self.map_bgl.deinit();
}

/// Queues a brickmap for upload.
///
/// This function will make a copy of the brickmap given.
///
/// This function is thread-safe.
pub fn queue_brickmap(self: *Self, at_coords: BrickmapCoordinates, brickmap: *const Brickmap) !void {
    self.bigass_mutex.lock();
    defer self.bigass_mutex.unlock();

    const alloc = self.brickmap_queue.allocator;

    const copy = try alloc.create(Brickmap);
    copy.* = brickmap.*;
    errdefer alloc.destroy(copy);

    try self.brickmap_queue.append(.{
        .coords = at_coords,
        .brickmap = copy,
    });
}

fn generate_brickgrid(self: *Self, brickgrid_origin: BrickmapCoordinates, alloc: std.mem.Allocator) ![]?usize {
    var ret = try alloc.alloc(?usize, self.config.grid_size());
    @memset(ret, null);

    for (self.brickmap_tracker, 0..self.config.no_brickmaps) |v, i| if (v.valid) {
        const g_brickmap_coords = wgm.cast(isize, v.brickmap_coords).?;
        const g_origin_coords = wgm.cast(isize, brickgrid_origin).?;

        const bl_brickmap_coords = wgm.sub(g_brickmap_coords, g_origin_coords);
        const below_bounds = wgm.compare(
            .some,
            bl_brickmap_coords,
            .less_than,
            [_]isize{0} ** 3,
        );
        const no_greater_than_bounds = wgm.compare(
            .all,
            bl_brickmap_coords,
            .less_than,
            wgm.cast(isize, self.config.grid_dimensions).?,
        );

        if (below_bounds or !no_greater_than_bounds) continue;

        const blc = wgm.cast(usize, bl_brickmap_coords).?;
        const idx = blc[0] +
            blc[1] * self.config.grid_dimensions[0] +
            blc[2] * (self.config.grid_dimensions[0] * self.config.grid_dimensions[1]);

        ret[idx] = i;
    };

    return ret;
}

fn find_slot(self: *Self, coord_hint: ?BrickmapCoordinates) usize {
    if (coord_hint) |w| {
        for (0..self.config.no_brickmaps, self.brickmap_tracker) |i, v| {
            if (v.valid and wgm.compare(.all, v.brickmap_coords, .equal, w)) {
                return i;
            }
        }
    }

    for (0..self.config.no_brickmaps, self.brickmap_tracker) |i, v| {
        if (!v.valid) return i;
    }

    @panic("there's no eviction strategy rn");
}

fn upload_brickmap(self: *Self, slot: usize, brickmap: *const Brickmap, queue: wgpu.Queue) void {
    if (Brickmap.Traits.NodeType == u8) {
        // uploading layer 1 is too much trouble for too little gain
        queue.write_buffer(self.bricktree_buffers[slot], 0, brickmap.tree[1..]);
    } else {
        @compileError("NYI: u64 trees");
    }

    // TODO: upload the actual thing
}

/// Call this before doing anything in render().
pub fn before_render(self: *Self, queue: wgpu.Queue) !void {
    const previous_queue = blk: {
        self.bigass_mutex.lock();
        defer self.bigass_mutex.unlock();

        const ret = self.brickmap_queue;

        self.brickmap_queue = std.ArrayList(QueuedBrickmap).init(g.biframe_alloc);

        break :blk ret;
    };

    for (previous_queue.items) |brickmap| {
        std.log.debug("brickmap!", .{});

        const slot = self.find_slot(brickmap.coords);

        self.upload_brickmap(slot, brickmap.brickmap, queue);

        const alloc = previous_queue.allocator;
        alloc.destroy(brickmap.brickmap);
    }

    previous_queue.deinit();

    const data = try g.frame_alloc.alloc(u32, self.config.grid_size());

    const local_brickgrid = try self.generate_brickgrid(.{ 0, 0, 0 }, g.frame_alloc);

    for (0..data.len) |i| {
        data[i] = if (local_brickgrid[i]) |v| @intCast(v) else std.math.maxInt(u32);
    }

    queue.write_texture(
        wgpu.ImageCopyTexture{
            .texture = self.brickgrid_texture,
        },
        std.mem.sliceAsBytes(data),
        wgpu.Extent3D{
            .width = @intCast(self.config.grid_dimensions[0]),
            .height = @intCast(self.config.grid_dimensions[1]),
            .depth_or_array_layers = @intCast(self.config.grid_dimensions[2]),
        },
        wgpu.TextureDataLayout{
            .offset = 0,
            .bytes_per_row = @intCast(self.config.grid_dimensions[0] * 4),
            .rows_per_image = @intCast(self.config.grid_dimensions[1]),
        },
    );
}
