const std = @import("std");

const mustache = @import("mustache");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const dyn = @import("dyn");
const wgm = @import("wgm");
const imgui = @import("imgui");

const PackedVoxel = @import("../../voxel.zig").PackedVoxel;
const Voxel = @import("../../voxel.zig").Voxel;

pub const Config2 = @import("defns.zig").Config2;
pub const ConfigArgs = @import("defns.zig").ConfigArgs;

const IBackend = @import("../IBackend.zig");
const IThing = @import("../../IThing.zig");
const IVoxelProvider = @import("../../IVoxelProvider.zig");

const g = &@import("../../main.zig").g;

pub const BrickgridEntry = union(enum) {
    NotChecked: void,

    Unoccupied: void,
    Occupied: usize,

    pub fn pack(self: BrickgridEntry) u32 {
        return switch (self) {
            .Occupied => |v| @intCast(v),
            .NotChecked => 0xFFFF_FFFF,
            .Unoccupied => 0xFFFF_FFFE,
        };
    }

    pub fn unpack(self: u32) BrickgridEntry {
        switch (self) {
            0xFFFF_FFFF => .{ .NotChecked = {} },
            0xFFFF_FFFE => .{ .Unoccupied = {} },
            else => {},
        }
    }
};

pub fn FeedbackBuffer(comptime no_entries: usize) type {
    return extern struct {
        next_idx: u32 = 0,
        data: [no_entries]u32,
    };
}

pub fn Backend(comptime Cfg: type) type {
    return struct {
        const Self = @This();

        pub const FBuffer = FeedbackBuffer(256);

        const Painter = @import("components/painter.zig").Painter(Cfg);
        const Storage = @import("components/storage.zig").Storage(Cfg);
        const Computer = @import("components/computer.zig").Computer(Cfg);

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

        pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IBackend });

        painter: *Painter,
        storage: *Storage,
        computer: *Computer,

        origin_brickmap: [3]isize = .{ 0, 0, 0 },

        config: ?MapConfig = null,
        brickmaps: []?[3]isize = &.{},
        brickgrid: []BrickgridEntry = &.{},
        feedback_buffer: FBuffer = std.mem.zeroes(FBuffer),

        map_bgl: wgpu.BindGroupLayout,
        map_bg: wgpu.BindGroup = .{},
        brickgrid_texture: wgpu.Texture = .{},
        brickgrid_texture_view: wgpu.TextureView = .{},
        brickgrid_feedback_buffer: wgpu.Buffer,
        brickgrid_feedback_read_buffer: wgpu.Buffer,
        bricktree_buffer: wgpu.Buffer = .{},
        brickmap_buffer: wgpu.Buffer = .{},

        pub fn init() !*Self {
            const self = try g.alloc.create(Self);

            const brickgrid_feedback_buffer = try g.device.create_buffer(.{
                .label = "brickgrid feedback buffer",
                .usage = .{
                    .copy_dst = true,
                    .copy_src = true,
                    .storage = true,
                },
                .size = @sizeOf(FBuffer),
                .mapped_at_creation = false,
            });
            errdefer brickgrid_feedback_buffer.deinit();

            const brickgrid_feedback_read_buffer = try g.device.create_buffer(.{
                .label = "brickgrid feedback read-buffer",
                .usage = .{
                    .copy_dst = true,
                    .map_read = true,
                },
                .size = @sizeOf(FBuffer),
                .mapped_at_creation = false,
            });
            errdefer brickgrid_feedback_read_buffer.deinit();

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
                            .type = .Storage,
                        } },
                    },
                    wgpu.BindGroupLayout.Entry{
                        .binding = 2,
                        .visibility = .{ .compute = true },
                        .layout = .{ .Buffer = .{
                            .type = .ReadOnlyStorage,
                        } },
                    },
                    wgpu.BindGroupLayout.Entry{
                        .binding = 3,
                        .visibility = .{ .compute = true },
                        .layout = .{ .Buffer = .{
                            .type = .ReadOnlyStorage,
                        } },
                    },
                })[0..if (Cfg.has_tree) 4 else 3],
            });
            errdefer map_bgl.deinit();

            const painter = try g.alloc.create(Painter);
            errdefer g.alloc.destroy(painter);
            painter.* = try Painter.init();
            errdefer painter.deinit();

            const storage = try g.alloc.create(Storage);
            errdefer g.alloc.destroy(storage);
            storage.* = try Storage.init();
            errdefer storage.deinit();

            const computer = try g.alloc.create(Computer);
            errdefer g.alloc.destroy(computer);
            computer.* = try Computer.init(map_bgl);
            errdefer computer.deinit();

            painter.backend = self;
            painter.storage = storage;
            painter.computer = computer;

            storage.backend = self;
            storage.painter = painter;
            storage.computer = computer;

            computer.backend = self;
            computer.painter = painter;
            computer.storage = storage;

            self.* = .{
                .painter = painter,
                .storage = storage,
                .computer = computer,

                .map_bgl = map_bgl,

                .brickgrid_feedback_buffer = brickgrid_feedback_buffer,
                .brickgrid_feedback_read_buffer = brickgrid_feedback_read_buffer,
            };
            errdefer self.deinit();

            try self.reconfigure(.{
                // .grid_dimensions = .{ 209, 3, 209 },
                // .no_brickmaps = (@as(usize, 1) << 31) / (Cfg.Brickmap.volume * 4) - 1,
                .grid_dimensions = .{ 1, 1, 1 },
                .no_brickmaps = 1,
            });

            return self;
        }

        pub fn deinit(self: *Self) void {
            // self.computer.deinit();
            // self.storage.deinit();

            self.painter.deinit();
            g.alloc.destroy(self.painter);

            self.storage.deinit();
            g.alloc.destroy(self.storage);

            self.computer.deinit();
            g.alloc.destroy(self.computer);

            self.reconfigure(null) catch unreachable;
        }

        pub fn resize(self: *Self, dims: [2]usize) !void {
            try self.computer.resize(dims);
        }

        pub fn do_gui(self: *Self) !void {
            self.computer.do_gui();
        }

        pub fn destroy(self: *Self, on_alloc: std.mem.Allocator) void {
            on_alloc.destroy(self);
        }

        fn get_view_volume_for(origin_brickmap: [3]isize, grid_dimensions: [3]usize) [2][3]isize {
            return wgm.mulew([_][3]isize{
                wgm.cast(isize, origin_brickmap).?,
                wgm.add(origin_brickmap, wgm.cast(isize, grid_dimensions).?),
            }, Cfg.Brickmap.side_length_i);
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

        fn rememo_brickgrid(self: *Self) void {
            @memset(self.brickgrid, .{ .NotChecked = {} });
            for (self.brickmaps, 0..) |maybe_g_bm_coords, bm_idx| if (maybe_g_bm_coords) |g_bm_coords| {
                const bgl_bm_coords = self.bm_coords_to_bgl_bm_coords(g_bm_coords).?;
                const bg_idx = self.bgl_bm_coords_to_bg_idx(bgl_bm_coords);
                self.brickgrid[bg_idx] = .{ .Occupied = bm_idx };
            };
        }

        pub fn recenter(self: *Self, desired_center: [3]f64) void {
            const center_brickmap = wgm.lossy_cast(isize, wgm.trunc(wgm.div(
                desired_center,
                wgm.lossy_cast(f64, Cfg.Brickmap.side_length),
            )));

            const origin = wgm.sub(
                center_brickmap,
                wgm.div(wgm.cast(isize, self.config.?.grid_dimensions).?, 2),
            );

            if (std.meta.eql(origin, self.origin_brickmap)) return;
            std.log.debug("recentering to {any} (origin bm: {any})", .{ desired_center, origin });

            const old_volume = self.get_view_volume();
            const volume = get_view_volume_for(origin, self.config.?.grid_dimensions);

            for (self.brickmaps) |v| if (v) |w| {
                const v_w = wgm.mulew(w, Cfg.Brickmap.side_length_i);
                if (wgm.compare(.all, v_w, .greater_than_equal, volume[0]) and //
                    wgm.compare(.all, v_w, .less_than, volume[1]))
                {
                    continue;
                }

                _ = self.remove_brickmap(w);
            };

            const bm_delta = wgm.sub(origin, self.origin_brickmap);
            const gd = self.config.?.grid_dimensions;
            for (0..gd[2]) |z| for (0..gd[1]) |y| for (0..gd[0]) |x| {
                const out_coords = [_]usize{
                    if (bm_delta[0] >= 0) x else gd[0] - x - 1,
                    if (bm_delta[1] >= 0) y else gd[1] - y - 1,
                    if (bm_delta[2] >= 0) z else gd[2] - z - 1,
                };
                const out_idx = self.bgl_bm_coords_to_bg_idx(out_coords);

                const in_coords_sgn = wgm.add(wgm.cast(isize, out_coords).?, bm_delta);
                const in_coords = wgm.cast(usize, in_coords_sgn) orelse {
                    self.brickgrid[out_idx] = .{ .NotChecked = {} };
                    continue;
                };
                if (wgm.compare(.some, in_coords, .greater_than_equal, gd)) {
                    self.brickgrid[out_idx] = .{ .NotChecked = {} };
                    continue;
                }

                const in_idx = self.bgl_bm_coords_to_bg_idx(in_coords);
                self.brickgrid[out_idx] = self.brickgrid[in_idx];
            };

            self.origin_brickmap = origin;

            // self.rememo_brickgrid();

            const already_drawn = .{
                .{
                    @max(old_volume[0][0], volume[0][0]),
                    @max(old_volume[0][1], volume[0][1]),
                    @max(old_volume[0][2], volume[0][2]),
                },
                .{
                    @min(old_volume[1][0], volume[1][0]),
                    @min(old_volume[1][1], volume[1][1]),
                    @min(old_volume[1][2], volume[1][2]),
                },
            };

            if (self.painter.already_drawn) |_| {
                // TODO: this can be handled with more grace
                self.painter.already_drawn = .{.{0} ** 3} ** 2;
            } else {
                self.painter.already_drawn = already_drawn;
            }
        }

        pub fn get_origin(self: Self) [3]f64 {
            return wgm.lossy_cast(f64, wgm.mulew(self.origin_brickmap, Cfg.Brickmap.side_length_i));
        }

        /// Converts _brickmap indices_ into _global brickmap coordinates_
        pub fn bm_idx_to_bm_coords(self: Self, bm_idx: usize) ?[3]isize {
            return self.brickmaps[bm_idx];
        }

        /// Converts _global brickmap coordinates_ into
        pub fn bm_coords_to_bgl_bm_coords(self: Self, g_bm_coords: [3]isize) ?[3]usize {
            const relative = wgm.cast(usize, wgm.sub(
                g_bm_coords,
                self.origin_brickmap,
            )) orelse return null;

            if (wgm.compare(.some, relative, .greater_than_equal, self.config.?.grid_dimensions)) {
                return null;
            }

            return relative;
        }

        /// Converts _brickgrid-local brickmap coordinates_ into flat brickgrid indices.
        fn bgl_bm_coords_to_bg_idx(self: Self, bgl_bm_coords: [3]usize) usize {
            return bgl_bm_coords[0] //
            + bgl_bm_coords[1] * self.config.?.grid_dimensions[0] //
            + bgl_bm_coords[2] * self.config.?.grid_dimensions[0] * self.config.?.grid_dimensions[1];
        }

        /// Converts _brickgrid-local brickmap coordinates_ into _brickmap indices_
        pub fn bgl_bm_coords_to_bm_entry(self: Self, bgl_bm_coords: [3]usize) BrickgridEntry {
            return self.brickgrid[self.bgl_bm_coords_to_bg_idx(bgl_bm_coords)];
        }

        /// Converts _global brickmap coordinates_ into _brickmap indices_
        pub fn bm_coords_to_bm_idx(self: Self, g_bm_coords: [3]isize) ?usize {
            const bgl_bm_coords = self.bm_coords_to_bgl_bm_coords(g_bm_coords) orelse return null;

            return switch (self.bgl_bm_coords_to_bm_entry(bgl_bm_coords)) {
                .Occupied => |v| v,
                else => null,
            };
        }

        /// If there exists a brickmap at the given _global brickmap coordinates_, returns the index thereof. Otherwise, if there's an empty brickmap slot, returns the index of said sot. Otherwise, returns null.
        pub fn find_bm_idx_for_bm_coords(self: Self, g_bm_coords: [3]isize) ?usize {
            if (self.bm_coords_to_bm_idx(g_bm_coords)) |v| return v;

            for (self.brickmaps, 0..) |v, i| if (v == null) return i;

            return null;
        }

        /// Tries to remove the brickmap at the given _global brickmap
        /// coordinates_ and returns true. If there exists no such brickmap,
        /// returns false.
        pub fn remove_brickmap(self: Self, g_bm_coords: [3]isize) bool {
            const bgl_bm_coords = if (self.bm_coords_to_bgl_bm_coords(g_bm_coords)) |v| v else return false;

            const bg_idx = self.bgl_bm_coords_to_bg_idx(bgl_bm_coords);

            const ret = switch (self.brickgrid[bg_idx]) {
                .Occupied => |bm_idx| blk: {
                    std.debug.assert(self.brickmaps[bm_idx] != null);
                    std.debug.assert(std.meta.eql(self.brickmaps[bm_idx].?, g_bm_coords));

                    self.brickmaps[bm_idx] = null;

                    break :blk true;
                },
                else => false,
            };
            self.brickgrid[bg_idx] = .{ .Unoccupied = {} };

            return ret;
        }

        /// For IBackend
        pub fn configure(self: *Self, config: IBackend.BackendConfig) anyerror!void {
            const grid_dims = wgm.div(config.desied_view_volume_size, Cfg.Brickmap.side_length);
            const no_brickmaps = config.buffer_size / (Cfg.Brickmap.volume * 4);

            try self.reconfigure(.{
                .grid_dimensions = .{
                    @max(grid_dims[0], 1),
                    @max(grid_dims[1], 1),
                    @max(grid_dims[2], 1),
                },
                .no_brickmaps = no_brickmaps,
            });
        }

        pub fn check_desync(self: Self) void {
            for (self.brickmaps, 0..) |maybe_g_bm_coords, bm_idx| {
                if (maybe_g_bm_coords) |g_bm_coords| {
                    const bgl_bm_coords = self.bm_coords_to_bgl_bm_coords(g_bm_coords).?;
                    const bg_idx = self.bgl_bm_coords_to_bg_idx(bgl_bm_coords);
                    switch (self.brickgrid[bg_idx]) {
                        .Occupied => |v| std.debug.assert(v == bm_idx),
                        else => @panic("expected an occupied bg entry"),
                    }
                } else {
                    for (self.brickgrid) |entry| switch (entry) {
                        .Occupied => |v| std.debug.assert(v != bm_idx),
                        else => {},
                    };
                }
            }
        }

        /// Guaranteed to not throw if `config == null`
        fn reconfigure(self: *Self, config: ?MapConfig) !void {
            const old_config = self.config;
            errdefer {
                self.reconfigure(old_config) catch @panic("failed to roll back the config");
            }

            if (old_config != null) {
                self.map_bg.deinit();
                self.brickgrid_texture_view.deinit();
                self.brickgrid_texture.deinit();
                // self.brickgrid_feedback_texture_view.deinit();
                // self.brickgrid_feedback_texture.deinit();
                self.brickmap_buffer.destroy();
                self.brickmap_buffer.deinit();
                if (Cfg.has_tree) {
                    self.bricktree_buffer.destroy();
                    self.bricktree_buffer.deinit();
                }
                g.alloc.free(self.brickmaps);
                g.alloc.free(self.brickgrid);
            }

            if (config) |cfg| {
                const brickmaps = try g.alloc.alloc(?[3]isize, cfg.no_brickmaps);
                errdefer g.alloc.free(brickmaps);
                @memset(brickmaps, null);

                const brickgrid = try g.alloc.alloc(BrickgridEntry, cfg.grid_size());
                errdefer g.alloc.free(brickgrid);
                @memset(brickgrid, .{ .NotChecked = {} });

                const bricktree_buffer_size: ?usize = if (!@hasDecl(Cfg, "bricktree")) null else Cfg.bytes_per_bricktree_buffer * cfg.no_brickmaps;

                const bricktree_buffer: wgpu.Buffer = if (bricktree_buffer_size) |v| try g.device.create_buffer(wgpu.Buffer.Descriptor{
                    .label = "master bricktree buffer",
                    .size = v,
                    .usage = .{
                        .copy_dst = true,
                        .storage = true,
                    },
                    .mapped_at_creation = false,
                }) else .{};

                const brickmap_buffer_size = Cfg.Brickmap.volume * 4 * cfg.no_brickmaps;
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

                const brickgrid_texture_desc = wgpu.Texture.Descriptor{
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
                };

                const brickgrid_texture = try g.device.create_texture(brickgrid_texture_desc);
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
                                .buffer = self.brickgrid_feedback_buffer,
                            } },
                        },
                        wgpu.BindGroup.Entry{
                            .binding = 2,
                            .resource = .{ .Buffer = .{
                                .buffer = brickmap_buffer,
                            } },
                        },
                        wgpu.BindGroup.Entry{
                            .binding = 3,
                            .resource = .{ .Buffer = .{
                                .buffer = bricktree_buffer,
                            } },
                        },
                    })[0..if (Cfg.has_tree) 4 else 3],
                });
                errdefer map_bg.deinit();

                self.config = cfg;

                self.brickmaps = brickmaps;
                self.brickgrid = brickgrid;

                self.painter.already_drawn = .{.{0} ** 3} ** 2;

                self.brickgrid_texture = brickgrid_texture;
                self.brickgrid_texture_view = brickgrid_texture_view;
                self.bricktree_buffer = bricktree_buffer;
                self.brickmap_buffer = brickmap_buffer;

                self.map_bg = map_bg;
            }
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

        pub fn upload_brickmap(self: *Self, g_bm_coords: [3]isize, map: *const Cfg.Brickmap, tree: *const Cfg.BricktreeStorage) bool {
            const bgl_bm_coords = self.bm_coords_to_bgl_bm_coords(g_bm_coords) orelse return false;
            const slot = if (self.find_bm_idx_for_bm_coords(g_bm_coords)) |v| v else return false;
            self.brickmaps[slot] = g_bm_coords;
            self.brickgrid[self.bgl_bm_coords_to_bg_idx(bgl_bm_coords)] = .{ .Occupied = slot };

            const brickmap_offset = (Cfg.Brickmap.volume * 4) * slot;
            g.queue.write_buffer(self.brickmap_buffer, brickmap_offset, std.mem.asBytes(map.c_flat()[0..]));

            if (Cfg.has_tree) switch (Cfg.BricktreeNode) {
                u8 => {
                    const tree_offset = Cfg.bytes_per_bricktree_buffer * slot;
                    g.queue.write_buffer(self.bricktree_buffer, tree_offset + 4, tree[1..]);

                    const tmp: [4]u8 = .{ tree[0], undefined, undefined, tree[0] };
                    g.queue.write_buffer(self.bricktree_buffer, tree_offset, tmp[0..]);
                },
                u64 => {
                    const tree_offset = Cfg.bytes_per_bricktree_buffer * slot;
                    g.queue.write_buffer(self.bricktree_buffer, tree_offset, std.mem.sliceAsBytes(tree[0..]));
                },
                else => unreachable,
            };

            return true;
        }

        fn translate_brickgrid(self: Self, local_brickgrid: []u32) void {
            @memset(local_brickgrid, std.math.maxInt(u32));

            for (self.brickgrid, 0..) |entry, i| {
                local_brickgrid[i] = entry.pack();
            }
        }

        pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
            std.mem.sort(u32, self.feedback_buffer.data[0..], {}, struct {
                pub fn aufruf(_: void, lhs: u32, rhs: u32) bool {
                    return lhs < rhs;
                }
            }.aufruf);

            const no_unique: usize = blk: {
                var last: u32 = std.math.maxInt(u32);
                var no_unique: usize = 0;
                for (self.feedback_buffer.data) |v| {
                    if (v == std.math.maxInt(u32)) break;
                    if (v == last) continue;
                    last = v;

                    self.feedback_buffer.data[no_unique] = v;
                    no_unique += 1;
                }
                break :blk no_unique;
            };

            const fb_to_write: FBuffer = .{ .data = .{std.math.maxInt(u32)} ** 256 };
            g.queue.write_buffer(self.brickgrid_feedback_buffer, 0, std.mem.asBytes(&fb_to_write));

            try self.painter.render(self.feedback_buffer.data[0..no_unique]);

            const local_brickgrid = g.frame_alloc.alloc(u32, self.config.?.grid_size()) catch @panic("OOM");

            self.translate_brickgrid(local_brickgrid);
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

            try self.computer.render(delta_ns, encoder, onto);

            encoder.copy_buffer_to_buffer(
                self.brickgrid_feedback_read_buffer,
                0,
                self.brickgrid_feedback_buffer,
                .{ 0, @sizeOf(FBuffer) },
            );
        }

        pub fn post_render(self: *Self) !void {
            const Context = struct {
                self: *Self,
                result_mutex: std.Thread.Mutex = .{},
                result_cv: std.Thread.Condition = .{},
                result_ready: bool = false,
            };

            var context: Context = .{ .self = self };
            self.brickgrid_feedback_read_buffer.map_async(
                .{ 0, @sizeOf(FBuffer) },
                .{ .read = true },
                struct {
                    pub fn aufruf(ctx_erased: *anyopaque, result: wgpu.Buffer.MapResult) void {
                        _ = result;
                        const _context: *Context = @ptrCast(@alignCast(ctx_erased));
                        _context.result_mutex.lock();
                        _context.result_ready = true;
                        _context.result_cv.signal();
                        _context.result_mutex.unlock();
                    }
                }.aufruf,
                @ptrCast(&context),
            );

            g.device.poll(true);

            // context.result_mutex.lock();
            // while (!context.result_ready) {
            //     context.result_cv.wait(&context.result_mutex);
            // }
            // context.result_mutex.unlock();

            const mapped_range = self.brickgrid_feedback_read_buffer.const_mapped_range(.{ 0, @sizeOf(FBuffer) });
            @memcpy(std.mem.asBytes(&self.feedback_buffer), mapped_range);
            self.brickgrid_feedback_read_buffer.unmap();
        }

        test {
            std.testing.refAllDecls(@import("bricktree/u8.zig"));
            std.testing.refAllDecls(@import("bricktree/u64.zig"));
            std.testing.refAllDecls(@import("bricktree/curves.zig"));
        }
    };
}
