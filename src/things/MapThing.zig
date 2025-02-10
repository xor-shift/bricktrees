const std = @import("std");

const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const brick = @import("../brick.zig");

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const AnyThing = @import("../AnyThing.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .deinit = Any.deinit,
            .destroy = Any.destroy,

            .render = Any.render,
        };
    }

    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn render(self_arg: *anyopaque, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(encoder, onto);
    }
};

pub const Brickmap = brick.U8Map(4);

pub const BrickmapInfo = struct {
    /// Whether the data on the GPU for this brickmap is junk
    valid: bool = false,

    /// I still am not sure what to do with this but i'm sure that we need
    /// something like this for when the brickgrid is shifted.
    /// Undefined if `!valid`.
    last_accessed: usize = undefined,

    /// Undefined if `!valid`.
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

alloc: std.mem.Allocator,

// TODO: accesses to this are a little racy
origin_brickmap: [3]isize = .{ 0, 0, 0 },

map_bgl: wgpu.BindGroupLayout,

queue_mutex: std.Thread.Mutex = .{},
brickmap_queue: std.ArrayList(QueuedBrickmap),

/// Do not edit directly. Call `reconfigure` instead.
config: ?MapConfig = null,
brickmap_tracker: []BrickmapInfo = &.{},
local_brickgrid: []u32 = &.{},

brickgrid_texture: wgpu.Texture = .{},
brickgrid_texture_view: wgpu.TextureView = .{},
bricktree_buffer: wgpu.Buffer = .{},
brickmap_buffer: wgpu.Buffer = .{},

map_bg: wgpu.BindGroup = .{},

/// You must call `reconfigure` or preferably `set_render_distance` after this.
pub fn init(alloc: std.mem.Allocator) !Self {
    const map_bgl = try g.device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
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
                } },
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 2,
                .visibility = .{ .compute = true },
                .layout = .{ .Buffer = .{
                    .type = .ReadOnlyStorage,
                } },
            },
        },
    });
    errdefer map_bgl.deinit();

    const brickmap_queue = std.ArrayList(QueuedBrickmap).init(g.biframe_alloc);

    return .{
        .alloc = alloc,

        .map_bgl = map_bgl,

        .brickmap_queue = brickmap_queue,
    };
}

pub fn deinit(self: *Self) void {
    self.map_bgl.deinit();

    self.reconfigure(null) catch unreachable;
}

pub fn to_any(self: *Self) AnyThing {
    return Any.init(self);
}

/// Guaranteed to not throw if `config == null`
pub fn reconfigure(self: *Self, config: ?MapConfig) !void {
    const old_self = self.*;
    errdefer {
        self.config = old_self.config;

        self.brickmap_tracker = old_self.brickmap_tracker;
        self.local_brickgrid = old_self.local_brickgrid;

        self.brickgrid_texture = old_self.brickgrid_texture;
        self.brickgrid_texture_view = old_self.brickgrid_texture_view;
        self.bricktree_buffer = old_self.bricktree_buffer;
        self.brickmap_buffer = old_self.brickmap_buffer;

        self.map_bg = old_self.map_bg;
    }

    if (self.config != null) {
        self.config = null;

        self.alloc.free(self.brickmap_tracker);
        self.alloc.free(self.local_brickgrid);

        self.bricktree_buffer.destroy();
        self.bricktree_buffer.deinit();

        self.brickmap_buffer.destroy();
        self.brickmap_buffer.deinit();

        self.brickgrid_texture_view.deinit();
        self.brickgrid_texture.deinit();

        self.map_bg.deinit();
    }

    const cfg = if (config) |v| v else return;

    const brickmap_tracker = try self.alloc.alloc(BrickmapInfo, cfg.no_brickmaps);
    errdefer self.alloc.free(brickmap_tracker);
    @memset(brickmap_tracker, .{});

    const local_brickgrid = try self.alloc.alloc(u32, cfg.grid_size());
    errdefer self.alloc.free(local_brickgrid);
    @memset(local_brickgrid, std.math.maxInt(u32));

    const bricktree_buffer_size = (Brickmap.Traits.no_tree_bits / 8 - 1) * cfg.no_brickmaps;
    const bricktree_buffer = try g.device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "master bricktree buffer",
        .size = bricktree_buffer_size,
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });

    const brickmap_buffer_size = Brickmap.Traits.volume * 4 * cfg.no_brickmaps;
    const brickmap_buffer = try g.device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "master brickmap buffer",
        .size = brickmap_buffer_size,
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });
    errdefer brickmap_buffer.deinit();

    const brickgrid_texture = try g.device.create_texture(wgpu.Texture.Descriptor{
        .label = "brickgrid texture",
        .size = .{
            .width = @intCast(cfg.grid_dimensions[0]),
            .height = @intCast(cfg.grid_dimensions[1]),
            .depth_or_array_layers = @intCast(cfg.grid_dimensions[2]),
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

    const map_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "map bg",
        .layout = self.map_bgl,
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

    self.config = cfg;

    self.brickmap_tracker = brickmap_tracker;
    self.local_brickgrid = local_brickgrid;

    self.brickgrid_texture = brickgrid_texture;
    self.brickgrid_texture_view = brickgrid_texture_view;
    self.bricktree_buffer = bricktree_buffer;
    self.brickmap_buffer = brickmap_buffer;

    self.map_bg = map_bg;
}

/// Queues a brickmap for upload.
///
/// This function will make a copy of the brickmap given.
///
/// This function is thread-safe.
pub fn queue_brickmap(self: *Self, at_coords: [3]isize, brickmap: *const Brickmap) !void {
    self.queue_mutex.lock();
    defer self.queue_mutex.unlock();

    const alloc = self.brickmap_queue.allocator;

    const copy = try alloc.create(Brickmap);
    copy.* = brickmap.*;
    errdefer alloc.destroy(copy);

    try self.brickmap_queue.append(.{
        .coords = at_coords,
        .brickmap = copy,
    });
}

fn bgl_coords_of(self: Self, brickmap_coords: [3]isize) ?[3]usize {
    const bgl_brickmap_coords = wgm.sub(brickmap_coords, self.origin_brickmap);

    const below_bounds = wgm.compare(
        .some,
        bgl_brickmap_coords,
        .less_than,
        [_]isize{0} ** 3,
    );
    const no_greater_than_bounds = wgm.compare(
        .all,
        bgl_brickmap_coords,
        .less_than,
        wgm.cast(isize, self.config.?.grid_dimensions).?,
    );

    if (below_bounds or !no_greater_than_bounds) return null;

    return wgm.cast(usize, bgl_brickmap_coords).?;
}

fn generate_brickgrid(self: *Self) void {
    @memset(self.local_brickgrid, std.math.maxInt(u32));

    for (self.brickmap_tracker, 0..) |v, i| if (v.valid) {
        const bgl_brickmap_coords = self.bgl_coords_of(v.brickmap_coords) orelse continue;

        // std.log.debug("{any} = {d}", .{bgl_brickmap_coords, i});

        const blc = wgm.cast(usize, bgl_brickmap_coords).?;
        const idx = blc[0] +
            blc[1] * self.config.?.grid_dimensions[0] +
            blc[2] * (self.config.?.grid_dimensions[0] * self.config.?.grid_dimensions[1]);

        self.local_brickgrid[idx] = @intCast(i);
    };
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

    for (0.., self.brickmap_tracker) |i, v| {
        if (self.bgl_coords_of(v.brickmap_coords) == null) return i;
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
}

/// Call this before doing anything in render().
pub fn render(self: *Self, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    const previous_queue = blk: {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        const ret = self.brickmap_queue;

        self.brickmap_queue = std.ArrayList(QueuedBrickmap).init(g.biframe_alloc);

        break :blk ret;
    };

    for (previous_queue.items) |brickmap| {
        const slot = self.find_slot(brickmap.coords);

        self.upload_brickmap(slot, brickmap.brickmap, g.queue);
        self.brickmap_tracker[slot] = .{
            .valid = true,
            .brickmap_coords = brickmap.coords,
        };

        const alloc = previous_queue.allocator;
        alloc.destroy(brickmap.brickmap);
    }

    previous_queue.deinit();

    self.generate_brickgrid();

    g.queue.write_texture(
        wgpu.ImageCopyTexture{
            .texture = self.brickgrid_texture,
        },
        std.mem.sliceAsBytes(self.local_brickgrid),
        wgpu.Extent3D{
            .width = @intCast(self.config.?.grid_dimensions[0]),
            .height = @intCast(self.config.?.grid_dimensions[1]),
            .depth_or_array_layers = @intCast(self.config.?.grid_dimensions[2]),
        },
        wgpu.TextureDataLayout{
            .offset = 0,
            .bytes_per_row = @intCast(self.config.?.grid_dimensions[0] * 4),
            .rows_per_image = @intCast(self.config.?.grid_dimensions[1]),
        },
    );
}
