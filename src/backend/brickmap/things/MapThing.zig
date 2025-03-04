const std = @import("std");

const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const curves = @import("../bricktree/curves.zig");

const AnyThing = @import("../../../AnyThing.zig");

const PackedVoxel = @import("../../../voxel.zig").PackedVoxel;
const Voxel = @import("../../../voxel.zig").Voxel;

const VoxelProvider = @import("../../../VoxelProvider.zig");

const g = &@import("../../../main.zig").g;

const Self = @This();

pub const Brickmap = switch (@import("scene_config").scene_config) {
    .brickmap => |config| @import("../brickmap.zig").Brickmap(config.bml_coordinate_bits),
    .brickmap_u8_bricktree => |config| @import("../brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
    .brickmap_u64_bricktree => |config| @import("../brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
    // else => @compileError("scene type not supported"),
};

pub const bricktree = switch (@import("scene_config").scene_config) {
    .brickmap => void,
    .brickmap_u8_bricktree => @import("../bricktree/u8.zig"),
    .brickmap_u64_bricktree => @import("../bricktree/u64.zig"),
    // else => @compileError("scene type not supported"),
};

pub const BricktreeStorage = switch (@import("scene_config").scene_config) {
    .brickmap => void,
    .brickmap_u8_bricktree => [bricktree.tree_bits(Brickmap.depth) / 8]u8,
    .brickmap_u64_bricktree => [bricktree.tree_bits(Brickmap.depth) / 64]u64,
    // else => @compileError("scene type not supported"),
};

const bytes_per_bricktree_buffer: usize = switch (@import("scene_config").scene_config) {
    .brickmap => undefined,
    .brickmap_u8_bricktree => bricktree.tree_bits(Brickmap.depth) / 8 + 3,
    .brickmap_u64_bricktree => bricktree.tree_bits(Brickmap.depth) / 8,
    // else => @compileError("scene type not supported"),
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

const QueueDirective = union(enum) {
    invalidate: struct {
        slot: usize,
    },

    queue: struct {
        map: *Brickmap,
        tree: *BricktreeStorage,
        slot: usize,
        coords: [3]isize,
    },
};

vtable_thing: AnyThing = AnyThing.mk_vtable(Self),

// TODO: accesses to this are a little racy
//
// somewhat of a correction to this todo: the dependency graph should solve
// the race issues but i'm not quite sure whether we want no locking here.
origin_brickmap: [3]isize = .{ 0, 0, 0 },

map_bgl: wgpu.BindGroupLayout,

queue_mutex: std.Thread.Mutex = .{},
brickmap_queue: std.ArrayList(QueueDirective),

/// Do not edit directly. Call `reconfigure` instead.
config: ?MapConfig = null,
brickmap_tracker: []?[3]isize = &.{},

brickgrid_texture: wgpu.Texture = .{},
brickgrid_texture_view: wgpu.TextureView = .{},
bricktree_buffer: wgpu.Buffer = .{},
brickmap_buffer: wgpu.Buffer = .{},

map_bg: wgpu.BindGroup = .{},

/// You must call `reconfigure` or preferably `set_render_distance` after this.
pub fn init() !Self {
    const map_bgl = try g.device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
        .label = "map bgl",
        .entries = ([_]wgpu.BindGroupLayout.Entry{
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
        })[0..if (bricktree == void) 2 else 3],
    });
    errdefer map_bgl.deinit();

    const brickmap_queue = std.ArrayList(QueueDirective).init(g.biframe_alloc);

    return .{
        .map_bgl = map_bgl,

        .brickmap_queue = brickmap_queue,
    };
}

pub fn deinit(self: *Self) void {
    self.map_bgl.deinit();

    self.reconfigure(null) catch unreachable;
}

/// Guaranteed to not throw if `config == null`
pub fn reconfigure(self: *Self, config: ?MapConfig) !void {
    const old_self = self.*;
    errdefer {
        self.config = old_self.config;

        self.brickmap_tracker = old_self.brickmap_tracker;

        self.brickgrid_texture = old_self.brickgrid_texture;
        self.brickgrid_texture_view = old_self.brickgrid_texture_view;
        self.bricktree_buffer = old_self.bricktree_buffer;
        self.brickmap_buffer = old_self.brickmap_buffer;

        self.map_bg = old_self.map_bg;
    }

    if (config) |cfg| {
        const brickmap_tracker = try g.alloc.alloc(?[3]isize, cfg.no_brickmaps);
        errdefer g.alloc.free(brickmap_tracker);
        @memset(brickmap_tracker, null);

        const bricktree_buffer_size: ?usize = if (bricktree == void) null else bytes_per_bricktree_buffer * cfg.no_brickmaps;

        const bricktree_buffer: wgpu.Buffer = if (bricktree_buffer_size) |v| try g.device.create_buffer(wgpu.Buffer.Descriptor{
            .label = "master bricktree buffer",
            .size = v,
            .usage = .{
                .copy_dst = true,
                .storage = true,
            },
            .mapped_at_creation = false,
        }) else .{};

        const brickmap_buffer_size = Brickmap.volume * 4 * cfg.no_brickmaps;
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
            .entries = ([_]wgpu.BindGroup.Entry{
                wgpu.BindGroup.Entry{
                    .binding = 0,
                    .resource = .{ .TextureView = brickgrid_texture_view },
                },
                wgpu.BindGroup.Entry{
                    .binding = 1,
                    .resource = .{ .Buffer = .{
                        .buffer = brickmap_buffer,
                    } },
                },
                wgpu.BindGroup.Entry{
                    .binding = 2,
                    .resource = .{ .Buffer = .{
                        .buffer = bricktree_buffer,
                    } },
                },
            })[0..if (bricktree == void) 2 else 3],
        });
        errdefer map_bg.deinit();

        self.config = cfg;

        self.brickmap_tracker = brickmap_tracker;

        self.brickgrid_texture = brickgrid_texture;
        self.brickgrid_texture_view = brickgrid_texture_view;
        self.bricktree_buffer = bricktree_buffer;
        self.brickmap_buffer = brickmap_buffer;

        self.map_bg = map_bg;
    }

    if (old_self.config != null) {
        self.config = null;

        g.alloc.free(self.brickmap_tracker);

        self.bricktree_buffer.destroy();
        self.bricktree_buffer.deinit();

        self.brickmap_buffer.destroy();
        self.brickmap_buffer.deinit();

        self.brickgrid_texture_view.deinit();
        self.brickgrid_texture.deinit();

        self.map_bg.deinit();
    }
}

/// Tries queueing a brickmap to be uploaded to the GPU. If the given brickmap
/// is empty, no queueing will take place and a `false` will be returned. The
/// return value is `true` otherwise.
///
/// This function is thread-safe.
pub fn queue_brickmap(self: *Self, at_coords: [3]isize, map: *const Brickmap) !bool {
    self.queue_mutex.lock();
    defer self.queue_mutex.unlock();

    const alloc = self.brickmap_queue.allocator;

    const tree = try alloc.create(BricktreeStorage);

    // const tree_gen_start = g.time();
    const is_empty = switch (@import("scene_config").scene_config) {
        .brickmap => std.mem.allEqual(u32, map.c_flat_u32()[0..], 0),
        .brickmap_u64_bricktree, .brickmap_u8_bricktree => |v| blk: {
            @memset(tree.*[0..], 0);
            bricktree.make_tree_inplace(Brickmap.depth, map, tree, switch (v.curve_kind) {
                .raster => curves.raster,
                .last_layer_morton => curves.llm,
            });

            break :blk tree[0] == 0;
        },
    };
    // const tree_gen_end = g.time();
    // std.log.debug("treegen took {d}ms", .{
    //     @as(f64, @floatFromInt(tree_gen_end - tree_gen_start)) / std.time.ns_per_ms
    // });
    // if (true) @panic("asd");

    if (is_empty) {
        return false;
    }

    const copy = try alloc.create(Brickmap);
    copy.* = map.*;

    try self.brickmap_queue.append(.{ .queue = .{
        .map = copy,
        .tree = tree,
        .coords = at_coords,
        .slot = 0,
    } });

    return true;
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

fn generate_brickgrid(self: *Self, local_brickgrid: []u32) void {
    @memset(local_brickgrid, std.math.maxInt(u32));

    for (self.brickmap_tracker, 0..) |v, i| if (v) |coords| {
        const bgl_brickmap_coords = self.bgl_coords_of(coords) orelse continue;

        // std.log.debug("{any} = {d}", .{bgl_brickmap_coords, i});

        const blc = wgm.cast(usize, bgl_brickmap_coords).?;
        const idx = blc[0] +
            blc[1] * self.config.?.grid_dimensions[0] +
            blc[2] * (self.config.?.grid_dimensions[0] * self.config.?.grid_dimensions[1]);

        local_brickgrid[idx] = @intCast(i);
    };
}

pub fn upload_brickmap(self: *Self, slot: usize, map: *const Brickmap, tree: *const BricktreeStorage) void {
    const brickmap_offset = (Brickmap.volume * 4) * slot;
    g.queue.write_buffer(self.brickmap_buffer, brickmap_offset, std.mem.asBytes(map.c_flat()[0..]));

    switch (@import("scene_config").scene_config) {
        .brickmap => {},
        .brickmap_u8_bricktree => {
            const tree_offset = bytes_per_bricktree_buffer * slot;
            g.queue.write_buffer(self.bricktree_buffer, tree_offset + 4, tree[1..]);

            const tmp: [4]u8 = .{ tree[0], undefined, undefined, tree[0] };
            g.queue.write_buffer(self.bricktree_buffer, tree_offset, tmp[0..]);
        },
        .brickmap_u64_bricktree => {
            const tree_offset = bytes_per_bricktree_buffer * slot;
            g.queue.write_buffer(self.bricktree_buffer, tree_offset, std.mem.sliceAsBytes(tree[0..]));
        },
    }
}

pub fn get_view_volume_for(origin_brickmap: [3]isize, grid_dimensions: [3]usize) [2][3]isize {
    return wgm.mulew([_][3]isize{
        wgm.cast(isize, origin_brickmap).?,
        wgm.add(origin_brickmap, wgm.cast(isize, grid_dimensions).?),
    }, Brickmap.side_length_i);
}

/// Returns the minimum and the maximum global-voxel-coordinate of the view volume
pub fn get_view_volume(self: Self) [2][3]isize {
    return get_view_volume_for(self.origin_brickmap, self.config.?.grid_dimensions);
}

pub fn sq_distance_to_center(self: Self, pt: [3]f64) f64 {
    const volume = wgm.lossy_cast(f64, self.get_view_volume());
    const center = wgm.div(wgm.add(volume[1], volume[0]), 2);
    const delta = wgm.sub(center, pt);
    return wgm.dot(delta, delta);
}

/// Tries to have it be so that the given point becomes the center of the view
/// volume. The actual origin of the view volume is returned.
pub fn recenter(self: *Self, desired_center: [3]f64) [3]f64 {
    const center_brickmap = wgm.lossy_cast(isize, wgm.trunc(wgm.div(
        desired_center,
        wgm.lossy_cast(f64, Brickmap.side_length),
    )));

    const origin = wgm.sub(
        center_brickmap,
        wgm.div(wgm.cast(isize, self.config.?.grid_dimensions).?, 2),
    );

    self.origin_brickmap = origin;

    return wgm.lossy_cast(f64, wgm.mulew(origin, Brickmap.side_length_i));
}

pub fn impl_thing_deinit(self: *Self) void {
    return self.deinit();
}

pub fn impl_thing_destroy(self: *Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn impl_thing_render(self: *Self, _: u64, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    const previous_queue = blk: {
        self.queue_mutex.lock();
        defer self.queue_mutex.unlock();

        const ret = self.brickmap_queue;

        self.brickmap_queue = std.ArrayList(QueueDirective).init(g.biframe_alloc);

        break :blk ret;
    };

    for (previous_queue.items) |directive| switch (directive) {
        .invalidate => |v| self.brickmap_tracker[v.slot] = null,
        .queue => |v| {
            std.log.debug("uploading {any} to {d}", .{v.coords, v.slot});
            self.upload_brickmap(v.slot, v.map, v.tree);
            self.brickmap_tracker[v.slot] = v.coords;
        },
    };

    previous_queue.deinit();

    const local_brickgrid = g.frame_alloc.alloc(u32, self.config.?.grid_size()) catch @panic("OOM");
    self.generate_brickgrid(local_brickgrid);

    g.queue.write_texture(
        wgpu.ImageCopyTexture{
            .texture = self.brickgrid_texture,
        },
        std.mem.sliceAsBytes(local_brickgrid),
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

