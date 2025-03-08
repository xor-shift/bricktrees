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

pub fn Backend(comptime Cfg: type) type {
    return struct {
        const Self = @This();

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
        brickmap_tracker: []?[3]isize = &.{},

        map_bgl: wgpu.BindGroupLayout,
        map_bg: wgpu.BindGroup = .{},
        brickgrid_texture: wgpu.Texture = .{},
        brickgrid_texture_view: wgpu.TextureView = .{},
        bricktree_buffer: wgpu.Buffer = .{},
        brickmap_buffer: wgpu.Buffer = .{},

        pub fn init() !*Self {
            const self = try g.alloc.create(Self);

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
                })[0..if (!@hasDecl(Cfg, "bricktree")) 2 else 3],
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

        pub fn recenter(self: *Self, desired_center: [3]f64) void {
            const center_brickmap = wgm.lossy_cast(isize, wgm.trunc(wgm.div(
                desired_center,
                wgm.lossy_cast(f64, Cfg.Brickmap.side_length),
            )));

            const origin = wgm.sub(
                center_brickmap,
                wgm.div(wgm.cast(isize, self.config.?.grid_dimensions).?, 2),
            );

            self.origin_brickmap = origin;
        }

        pub fn get_origin(self: Self) [3]f64 {
            return wgm.lossy_cast(f64, wgm.mulew(self.origin_brickmap, Cfg.Brickmap.side_length_i));
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

        /// Guaranteed to not throw if `config == null`
        fn reconfigure(self: *Self, config: ?MapConfig) !void {
            const old_config = self.config;
            errdefer {
                self.reconfigure(old_config) catch @panic("failed to roll back the config");
            }

            self.map_bg.deinit();
            self.brickgrid_texture_view.deinit();
            self.brickgrid_texture.deinit();
            self.brickmap_buffer.destroy();
            self.brickmap_buffer.deinit();
            if (Cfg.has_tree) {
                self.bricktree_buffer.destroy();
                self.bricktree_buffer.deinit();
            }
            g.alloc.free(self.brickmap_tracker);

            if (config) |cfg| {
                const brickmap_tracker = try g.alloc.alloc(?[3]isize, cfg.no_brickmaps);
                errdefer g.alloc.free(brickmap_tracker);
                @memset(brickmap_tracker, null);

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
                    })[0..if (Cfg.has_tree) 3 else 2],
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

        pub fn upload_brickmap(self: *Self, slot: usize, map: *const Cfg.Brickmap, tree: *const Cfg.BricktreeStorage) void {
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
        }

        pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
            try self.painter.render();

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

            try self.computer.render(delta_ns, encoder, onto);
        }

        test {
            std.testing.refAllDecls(@import("bricktree/u8.zig"));
            std.testing.refAllDecls(@import("bricktree/u64.zig"));
            std.testing.refAllDecls(@import("bricktree/curves.zig"));
        }
    };
}
