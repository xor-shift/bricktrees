const std = @import("std");

const mustache = @import("mustache");

const dyn = @import("dyn");
const wgm = @import("wgm");
const imgui = @import("imgui");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const curves = @import("bricktree/curves.zig");
const worker_pool = @import("../../worker_pool.zig");

const CameraThing = @import("../../things/CameraThing.zig");
const VisualiserThing = @import("../../things/VisualiserThing.zig");

const PackedVoxel = @import("../../voxel.zig").PackedVoxel;
const Voxel = @import("../../voxel.zig").Voxel;

test {
    // std.testing.refAllDecls(@import("brickmap.zig"));
    // std.testing.refAllDecls(@import("things/MapThing.zig"));
    // std.testing.refAllDecls(@import("things/GpuThing.zig"));
    // std.testing.refAllDecls(@import("things/VoxelThing.zig"));
    // std.testing.refAllDecls(@import("bricktree/u8.zig"));
    // std.testing.refAllDecls(@import("bricktree/u64.zig"));
    // std.testing.refAllDecls(@import("bricktree/curves.zig"));
}

const IBackend = @import("../IBackend.zig");
const IThing = @import("../../IThing.zig");
const IVoxelProvider = @import("../../IVoxelProvider.zig");

const g = &@import("../../main.zig").g;

const Self = @This();

/// Be careful: the vecN<T> of WGSL and the [N]T of C/Zig may not have the same alignment!
const Uniforms = extern struct {
    random_seed: [8]u32 = .{0} ** 8,

    transform: [4][4]f32 = wgm.identity(f32, 4),
    inverse_transform: [4][4]f32 = wgm.identity(f32, 4),

    brickgrid_origin: [3]i32 = .{0} ** 3,
    _padding_0: u32 = undefined,

    dims: [2]f32 = .{ 0, 0 },
    _padding_1: u32 = undefined,
    _padding_2: u32 = undefined,

    debug_variable_0: u32 = 0,
    debug_variable_1: u32 = 0,
    debug_mode: u32 = 0,
    debug_level: u32 = 0,
};

pub const Brickmap = switch (@import("scene_config").scene_config) {
    .brickmap => |config| @import("brickmap.zig").Brickmap(config.bml_coordinate_bits),
    .brickmap_u8_bricktree => |config| @import("brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
    .brickmap_u64_bricktree => |config| @import("brickmap.zig").Brickmap(config.base_config.bml_coordinate_bits),
};

pub const bricktree = switch (@import("scene_config").scene_config) {
    .brickmap => void,
    .brickmap_u8_bricktree => @import("bricktree/u8.zig"),
    .brickmap_u64_bricktree => @import("bricktree/u64.zig"),
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

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IBackend });

origin_brickmap: [3]isize = .{ 0, 0, 0 },

config: ?MapConfig = null,
brickmap_tracker: []?[3]isize = &.{},
brickgrid_memo: []?usize = &.{},

cached_origin: [3]isize = .{ 0, 0, 0 },
cached_config: ?MapConfig = null,
brickmap_gen_pool: *Pool,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup = .{},
brickgrid_texture: wgpu.Texture = .{},
brickgrid_texture_view: wgpu.TextureView = .{},
bricktree_buffer: wgpu.Buffer = .{},
brickmap_buffer: wgpu.Buffer = .{},

compute_shader: wgpu.ShaderModule,

uniform_bgl: wgpu.BindGroupLayout,
uniform_bg: wgpu.BindGroup,
uniform_buffer: wgpu.Buffer,
uniforms: Uniforms = .{
    .dims = .{
        @floatFromInt(@TypeOf(g.*).default_resolution[0]),
        @floatFromInt(@TypeOf(g.*).default_resolution[1]),
    },
},
rand: std.Random.Xoshiro256,

compute_textures_bgl: wgpu.BindGroupLayout,
compute_textures_bg: wgpu.BindGroup,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

fn make_shader(alloc: std.mem.Allocator) !wgpu.ShaderModule {
    const templated_code = val: {
        const cwd = std.fs.cwd();

        const file = try cwd.openFile("shaders/compute.wgsl", .{});
        defer file.close();

        const contents = try file.readToEndAllocOptions(alloc, 64 * 1024 * 1024, null, @alignOf(u8), 0);

        break :val contents;
    };
    defer alloc.free(templated_code);

    const maybe_res = try mustache.parseText(alloc, templated_code, .{}, .{
        .copy_strings = false,
    });

    const res = switch (maybe_res) {
        .parse_error => return error.ParseError,
        .success => |v| v,
    };

    defer res.deinit(alloc);

    var out = std.ArrayList(u8).init(alloc);
    const scene_config = @import("scene_config");
    try mustache.render(res, scene_config.MustacheSettings.from_config(scene_config.scene_config), out.writer());
    defer out.deinit();

    const shader_code = try out.toOwnedSliceSentinel(0);
    defer alloc.free(shader_code);

    const shader = try g.device.create_shader_module_wgsl("compute shader", shader_code);

    return shader;
}

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

    const compute_shader = try make_shader(g.alloc);
    errdefer compute_shader.deinit();

    const uniform_buffer = try g.device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "uniform buffer",
        .usage = .{
            .uniform = true,
            .copy_dst = true,
        },
        .size = @sizeOf(Uniforms),
    });
    errdefer uniform_buffer.deinit();

    const uniform_bgl = try g.device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
        .label = "uniform bgl",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .compute = true, .vertex = true, .fragment = true },
                .layout = .{ .Buffer = .{
                    .type = .Uniform,
                } },
            },
        },
    });
    errdefer uniform_bgl.deinit();

    const uniform_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "compute uniform bg",
        .layout = uniform_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{
                    .Buffer = .{
                        .buffer = uniform_buffer,
                        .offset = 0,
                        .size = @sizeOf(Uniforms),
                    },
                },
            },
        },
    });
    errdefer uniform_bg.deinit();

    const compute_textures_bgl = try g.device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
        .label = "compute textures' BGL",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .compute = true },
                .layout = .{ .StorageTexture = .{
                    .view_dimension = .D2,
                    .access = .WriteOnly,
                    .format = .BGRA8Unorm,
                } },
            },
        },
    });
    errdefer compute_textures_bgl.deinit();

    const compute_pipeline_layout = try g.device.create_pipeline_layout(wgpu.PipelineLayout.Descriptor{
        .label = "compute pipeline layout",
        .bind_group_layouts = &.{ uniform_bgl, compute_textures_bgl, map_bgl },
    });
    errdefer compute_pipeline_layout.deinit();

    const compute_pipeline = try g.device.create_compute_pipeline(wgpu.ComputePipeline.Descriptor{
        .label = "compute pipeline",
        .layout = compute_pipeline_layout,
        .compute = .{
            .module = compute_shader,
            .entry_point = "cs_main",
            .constants = &.{},
        },
    });
    errdefer compute_pipeline.deinit();

    var self: Self = .{
        .map_bgl = map_bgl,

        .compute_shader = compute_shader,

        .uniform_bgl = uniform_bgl,
        .uniform_bg = uniform_bg,
        .uniform_buffer = uniform_buffer,
        .rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64)),

        .compute_textures_bgl = compute_textures_bgl,
        .compute_textures_bg = .{},

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,

        .brickmap_gen_pool = try Pool.init(@min(std.Thread.getCpuCount() catch 1, 14), g.alloc, Self.pool_producer_fn, Self.pool_worker_fn),
    };
    errdefer self.deinit();

    try self.reconfigure(.{
        // .grid_dimensions = .{ 209, 3, 209 },
        // .no_brickmaps = 65535 * 2 - 27,
        .grid_dimensions = .{ 19, 15, 19 },
        // .grid_dimensions = .{ 3, 3, 3},
        .no_brickmaps = 31 * 15 * 31,
    });

    return self;
}

pub fn deinit(self: *Self) void {
    self.brickmap_gen_pool.deinit();
    g.alloc.destroy(self.brickmap_gen_pool);
    self.reconfigure(null) catch unreachable;
}

pub fn resize(self: *Self, dims: [2]usize) !void {
    self.uniforms.dims = .{
        @floatFromInt(dims[0]),
        @floatFromInt(dims[1]),
    };

    const visualiser = g.get_thing("visualiser").? //
        .get_concrete(VisualiserThing);

    const compute_textures_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "compute textures' BG",
        .layout = self.compute_textures_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .TextureView = visualiser.visualisation_texture.view },
            },
        },
    });
    errdefer compute_textures_bg.deinit();

    self.compute_textures_bg.deinit();
    self.compute_textures_bg = compute_textures_bg;
}

pub fn do_gui(self: *Self) !void {
    if (imgui.begin("asd", null, .{})) {
        _ = imgui.button("asdf", null);

        _ = imgui.input_scalar(u32, "debug mode", &self.uniforms.debug_mode, 1, 1);
        _ = imgui.input_scalar(u32, "debug level", &self.uniforms.debug_level, 1, 1);
        _ = imgui.input_scalar(u32, "debug variable 0", &self.uniforms.debug_variable_0, 1, 1);
        _ = imgui.input_scalar(u32, "debug variable 1", &self.uniforms.debug_variable_1, 1, 1);
    }
    imgui.end();
}

pub fn destroy(self: *Self, on_alloc: std.mem.Allocator) void {
    on_alloc.destroy(self);
}

fn reconfigure_voxel_stuff(self: *Self, config: ?MapConfig) !void {
    defer self.cached_config = config;

    const old_self = self;
    errdefer @panic("yeah");

    if (config) |v| {
        const new_memo = try g.alloc.alloc(?usize, v.grid_size());
        errdefer g.alloc.free(new_memo);
        @memset(new_memo, null);

        self.brickgrid_memo = new_memo;
    }

    if (old_self.cached_config != null) {
        g.alloc.free(self.brickgrid_memo);
    }
}

fn abs_to_memo(self: Self, abs_bm_coords: [3]isize) ?usize {
    const relative = wgm.cast(usize, wgm.sub(
        abs_bm_coords,
        self.cached_origin,
    )) orelse return null;

    const dims = self.cached_config.?.grid_dimensions;

    return relative[2] * dims[1] * dims[0] //
    + relative[1] * dims[0] //
    + relative[0]; //
}

fn set_memo(self: *Self, abs_bm_coords: [3]isize, val: ?usize) bool {
    self.brickgrid_memo[self.abs_to_memo(abs_bm_coords) orelse return false] = val;

    return true;
}

fn get_memo(self: Self, abs_bm_coords: [3]isize) ?usize {
    return self.brickgrid_memo[self.abs_to_memo(abs_bm_coords) orelse return null];
}

fn reconstruct_memo(self: *Self) void {
    @memset(self.brickgrid_memo, null);
    for (self.brickmap_tracker, 0..) |maybe_abs, i| if (maybe_abs) |abs| {
        _ = self.set_memo(abs, i);
    };
}

/// Tries to have it be so that the given point becomes the center of the view
/// volume. The actual origin of the view volume is returned.
fn recenter_camera(self: *Self, desired_center: [3]f64) [3]f64 {
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

/// Returns the area (in brickmaps) that should be kept the same.
fn recenter_voxel(self: *Self, origin: [3]isize) [2][3]isize {
    const old_volume = get_view_volume_for(self.cached_origin, self.config.?.grid_dimensions);

    self.cached_origin = origin;

    const volume = self.get_view_volume();

    for (self.brickmap_tracker, 0..) |v, i| if (v) |w| {
        const v_w = wgm.mulew(w, Brickmap.side_length_i);
        if (wgm.compare(.all, v_w, .greater_than_equal, volume[0]) and //
            wgm.compare(.all, v_w, .less_than, volume[1]))
        {
            continue;
        }

        self.brickmap_tracker[i] = null;
    };

    self.reconstruct_memo();

    return .{
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
}

pub fn sq_distance_to_center(self: Self, pt: [3]f64) f64 {
    const volume = wgm.lossy_cast(f64, self.get_view_volume());
    const center = wgm.div(wgm.add(volume[1], volume[0]), 2);
    const delta = wgm.sub(center, pt);
    return wgm.dot(delta, delta);
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

fn find_slot(self: *Self, for_coords: [3]isize) ?usize {
    if (self.get_memo(for_coords)) |v| return v;

    for (self.brickmap_tracker, 0..) |v, i| if (v == null) return i;

    return null;
}

pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    {
        const voxel_providers: []dyn.Fat(*IVoxelProvider) = blk: {
            var list = std.ArrayList(dyn.Fat(*IVoxelProvider)).init(g.frame_alloc);

            var iter = g.thing_store.things.iterator();
            while (iter.next()) |thing| {
                const vp = thing.value_ptr.sideways_cast(IVoxelProvider) orelse continue;
                try list.append(vp);
            }

            break :blk try list.toOwnedSlice();
        };

        const redraw_everything = if (!std.meta.eql(self.cached_config, self.config)) blk: {
            try self.reconfigure_voxel_stuff(self.config);
            break :blk true;
        } else false;

        const already_drawn_range = if (!std.mem.eql(isize, &self.origin_brickmap, &self.cached_origin))
            self.recenter_voxel(self.origin_brickmap)
        else
            self.get_view_volume();

        for (voxel_providers) |p| {
            p.d("voxel_draw_start", .{});
        }

        defer for (voxel_providers) |p| {
            p.d("voxel_draw_end", .{});
        };

        var context: PoolContext = .{
            .self = self,
            .voxel_providers = voxel_providers,

            .curve = .{
                .dims = self.config.?.grid_dimensions,
            },

            .redraw_everything = redraw_everything,
            .already_drawn_range = already_drawn_range,
        };
        self.brickmap_gen_pool.begin_work(&context);

        while (self.brickmap_gen_pool.get_result()) |info| {
            const result = info.result;
            const absolute_bm_coords = info.for_work.brickmap_coords;

            const the_brickmap = &result.brickmap;
            const the_bricktree = &result.bricktree;

            if (result.is_empty) {
                if (self.get_memo(absolute_bm_coords)) |slot| {
                    self.brickmap_tracker[slot] = null;
                    _ = self.set_memo(absolute_bm_coords, null);
                }
            } else if (self.find_slot(absolute_bm_coords)) |slot| {
                self.upload_brickmap(slot, the_brickmap, the_bricktree);
                self.brickmap_tracker[slot] = absolute_bm_coords;
                _ = self.set_memo(absolute_bm_coords, slot);
            }
        }
    }

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

    const dims = g.window.get_size() catch @panic("g.window.get_size()");

    const camera = g.get_thing("camera").?.get_concrete(CameraThing);

    self.rand.fill(std.mem.asBytes(&self.uniforms.random_seed));
    self.uniforms.transform = wgm.lossy_cast(f32, camera.cached_transform);
    self.uniforms.inverse_transform = wgm.lossy_cast(f32, camera.cached_transform_inverse);

    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&self.uniforms));

    {
        const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
            .label = "compute pass",
        });

        compute_pass.set_pipeline(self.compute_pipeline);
        compute_pass.set_bind_group(0, self.uniform_bg, null);
        compute_pass.set_bind_group(1, self.compute_textures_bg, null);
        compute_pass.set_bind_group(2, self.map_bg, null);

        const wg_sz: [2]usize = .{ 8, 8 };
        const wg_count = wgm.div(
            wgm.sub(
                wgm.add(dims, wg_sz),
                [2]usize{ 1, 1 },
            ),
            wg_sz,
        );
        compute_pass.dispatch_workgroups(.{
            @intCast(wg_count[0]),
            @intCast(wg_count[1]),
            1,
        });

        compute_pass.end();
        compute_pass.deinit();
    }
}

const Curve = struct {
    iteration: usize = 0,
    dims: [3]usize,

    fn next(ctx: *Curve) ?[3]usize {
        const z = ctx.iteration / (ctx.dims[1] * ctx.dims[0]);
        const y = (ctx.iteration / ctx.dims[0]) % ctx.dims[1];
        const x = ctx.iteration % ctx.dims[0];

        if (z >= ctx.dims[2]) return null;

        ctx.iteration += 1;

        return .{ x, y, z };
    }
};

const PoolContext = struct {
    self: *Self,
    voxel_providers: []dyn.Fat(*IVoxelProvider) = &.{},

    curve: Curve,

    redraw_everything: bool,
    already_drawn_range: [2][3]isize,
};

const PoolWork = struct {
    brickmap_coords: [3]isize,
    range: [2][3]isize,
};

const PoolResult = struct {
    is_empty: bool,
    brickmap: Brickmap,
    bricktree: BricktreeStorage,
};

const Pool = worker_pool.WorkerPool(PoolContext, PoolWork, PoolResult);

fn should_draw(ctx: *PoolContext, range: [2][3]isize) bool {
    const should_draw_from_scratch = //
        ctx.redraw_everything or //
        wgm.compare(.some, range[0], .less_than, ctx.already_drawn_range[0]) or //
        wgm.compare(.some, range[1], .greater_than, ctx.already_drawn_range[1]);

    const someone_wants_to_draw = if (should_draw_from_scratch) blk: {
        for (ctx.voxel_providers) |p| {
            if (p.d("should_draw_voxels", .{range})) {
                break :blk true;
            }
        }
        break :blk false;
    } else false;

    const someone_wants_to_redraw = if (!should_draw_from_scratch) blk: {
        for (ctx.voxel_providers) |p| {
            if (p.d("should_redraw_voxels", .{range})) {
                break :blk true;
            }
        }
        break :blk false;
    } else false;

    return someone_wants_to_redraw or someone_wants_to_draw;
}

fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
    while (true) {
        const vv_local_coords = ctx.curve.next() orelse return null;
        const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.origin_brickmap);

        const voxel_coords = wgm.mulew(abs_coords, Brickmap.side_length_i);
        const range = [_][3]isize{
            voxel_coords,
            wgm.add(voxel_coords, Brickmap.side_length_i),
        };

        if (!should_draw(ctx, range)) {
            continue;
        }

        return PoolWork{
            .brickmap_coords = abs_coords,
            .range = range,
        };
    }
}

fn pool_worker_fn(ctx: *PoolContext, out_result: *PoolResult, work: PoolWork) void {
    const voxel_storage = out_result.brickmap.flat()[0..];
    @memset(voxel_storage, std.mem.zeroes(PackedVoxel));

    for (ctx.voxel_providers) |p| {
        p.d("draw_voxels", .{ work.range, voxel_storage });
    }

    const as_brickmap: *Brickmap = @ptrCast(voxel_storage.ptr);

    const is_empty = switch (@import("scene_config").scene_config) {
        .brickmap => std.mem.allEqual(u32, as_brickmap.c_flat_u32()[0..], 0),
        .brickmap_u64_bricktree, .brickmap_u8_bricktree => |v| blk: {
            @memset(out_result.bricktree[0..], 0);
            bricktree.make_tree_inplace(Brickmap.depth, as_brickmap, &out_result.bricktree, switch (v.curve_kind) {
                .raster => curves.raster,
                .last_layer_morton => curves.llm,
            });

            break :blk out_result.bricktree[0] == 0;
        },
    };

    out_result.is_empty = is_empty;
}
