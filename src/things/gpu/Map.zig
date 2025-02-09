const std = @import("std");

const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const brick = @import("../../brick.zig");

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const g = &@import("../../main.zig").g;

const Self = @This();

pub const Brickmap = brick.U8Map(5);

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
    brickmap_coords: [3]isize = undefined,
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
    coords: [3]isize,
};

config: MapConfig,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
brickgrid_texture: wgpu.Texture,
brickgrid_texture_view: wgpu.TextureView,

bigass_mutex: std.Thread.Mutex = .{},

brickmap_queue: std.ArrayList(QueuedBrickmap),

bricktree_buffer: wgpu.Buffer,
brickmap_buffer: wgpu.Buffer,

alloc: std.mem.Allocator,

brickmap_tracker: []BrickmapInfo,

pub fn init(alloc: std.mem.Allocator, device: wgpu.Device, config: MapConfig) !Self {
    const brickmap_tracker = try alloc.alloc(BrickmapInfo, config.no_brickmaps);
    errdefer alloc.free(brickmap_tracker);
    @memset(brickmap_tracker, .{});

    const bricktree_buffer_size = (Brickmap.Traits.no_tree_bits / 8 - 1) * config.no_brickmaps;
    const bricktree_buffer = try device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "master bricktree buffer",
        .size = bricktree_buffer_size,
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });

    const brickmap_buffer_size = Brickmap.Traits.side_length * Brickmap.Traits.side_length * Brickmap.Traits.side_length * 4 * config.no_brickmaps;
    const brickmap_buffer = try device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "master brickmap buffer",
        .size = brickmap_buffer_size,
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });

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
                    .min_binding_size = bricktree_buffer_size,
                } },
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 2,
                .visibility = .{ .compute = true },
                .layout = .{ .Buffer = .{
                    .type = .ReadOnlyStorage,
                    .min_binding_size = brickmap_buffer_size,
                } },
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
                .resource = .{ .Buffer = .{
                    .buffer = bricktree_buffer,
                } },
            },
            wgpu.BindGroup.Entry{
                .binding = 2,
                .resource = .{ .Buffer = .{
                    .buffer = brickmap_buffer,
                } },
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

        .bricktree_buffer = bricktree_buffer,
        .brickmap_buffer = brickmap_buffer,

        .alloc = alloc,

        .brickmap_tracker = brickmap_tracker,
    };
}

pub fn deinit(self: *Self) void {
    self.map_bg.deinit();
    self.map_bgl.deinit();

    self.brickgrid_texture.deinit();
    self.bricktree_buffer.deinit();
    self.brickmap_buffer.deinit();

    self.alloc.free(self.brickmap_tracker);
}

/// Queues a brickmap for upload.
///
/// This function will make a copy of the brickmap given.
///
/// This function is thread-safe.
pub fn queue_brickmap(self: *Self, at_coords: [3]isize, brickmap: *const Brickmap) !void {
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

fn generate_brickgrid(self: *Self, brickgrid_origin: [3]isize, alloc: std.mem.Allocator) ![]?usize {
    var ret = try alloc.alloc(?usize, self.config.grid_size());
    @memset(ret, null);

    for (self.brickmap_tracker, 0..) |v, i| if (v.valid) {
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

fn find_slot(self: *Self, coord_hint: ?[3]isize) usize {
    if (coord_hint) |w| {
        for (0.., self.brickmap_tracker) |i, v| {
            if (v.valid and wgm.compare(.all, v.brickmap_coords, .equal, w)) {
                return i;
            }
        }
    }

    for (0.., self.brickmap_tracker) |i, v| {
        if (!v.valid) return i;
    }

    @panic("there's no eviction strategy rn");
}

fn upload_brickmap(self: *Self, slot: usize, brickmap: *const Brickmap, queue: wgpu.Queue) void {
    if (Brickmap.Traits.NodeType == u8) {
        // uploading layer 1 is too much trouble for too little gain
        const tree_offset = (Brickmap.Traits.no_tree_bits / 8 - 1) * slot;
        queue.write_buffer(self.bricktree_buffer, tree_offset, brickmap.tree[1..]);

        const brickmap_offset = (Brickmap.Traits.volume * 4) * slot;
        queue.write_buffer(self.brickmap_buffer, brickmap_offset, std.mem.asBytes(brickmap.voxels[0..]));
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
        self.brickmap_tracker[slot] = .{
            .valid = true,
            .brickmap_coords = brickmap.coords,
        };

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
