const std = @import("std");

const wgm = @import("wgm");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const brick = @import("../brick.zig");

const AnyThing = @import("../AnyThing.zig");
const Map = @import("gpu/Map.zig");
const TextureAndView = @import("gpu/TextureAndView.zig");

const Brickmap = Map.Brickmap;

const PackedVoxel = brick.PackedVoxel;
const Voxel = brick.Voxel;

const BrickmapCoordinates = brick.BrickmapCoordinates;
const VoxelCoordinates = brick.VoxelCoordinates;

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .deinit = Any.deinit,
            .destroy = Any.destroy,
            .on_resize = Any.on_resize,
            .on_raw_event = Any.on_raw_event,

            .do_gui = Any.do_gui,
            .render = Any.render,
        };
    }

    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn on_resize(self_arg: *anyopaque, dims: [2]usize) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_resize(dims);
    }

    pub fn on_raw_event(self_arg: *anyopaque, ev: sdl.c.SDL_Event) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_raw_event(ev);
    }

    pub fn do_gui(self_arg: *anyopaque) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).do_gui();
    }

    pub fn render(self_arg: *anyopaque, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(encoder, onto);
    }
};

// Be careful: the vecN<T> of WGSL and the [N]T of C/Zig may not have the same alignment!
const Uniforms = extern struct {
    transform: [4][4]f32 = wgm.identity(f32, 4),
    inverse_transform: [4][4]f32 = wgm.identity(f32, 4),

    dims: [2]f32,
    debug_mode: u32 = 0,
    debug_level: u32 = 0,

    pos: [3]f32 = .{ 0, 0, 0 }, // redundant
    _padding_0: u32 = undefined,

    brickgrid_origin: [3]i32 = .{0} ** 3,
    _padding_1: u32 = undefined,
};

compute_shader: wgpu.ShaderModule,
visualisation_shader: wgpu.ShaderModule,

uniforms: Uniforms = .{
    .dims = .{
        @floatFromInt(@TypeOf(g.*).default_resolution[0]),
        @floatFromInt(@TypeOf(g.*).default_resolution[1]),
    },
},
uniform_buffer: wgpu.Buffer,
uniform_bgl: wgpu.BindGroupLayout,
uniform_bg: wgpu.BindGroup,

visualisation_texture_bgl: wgpu.BindGroupLayout,
visualisation_texture_bg: wgpu.BindGroup,
visualisation_texture_sampler: wgpu.Sampler,
visualisation_texture: TextureAndView,

visualisation_pipeline_layout: wgpu.PipelineLayout,
visualisation_pipeline: wgpu.RenderPipeline,

map: Map,

compute_textures_bgl: wgpu.BindGroupLayout,
compute_textures_bg: wgpu.BindGroup,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

pub fn init(alloc: std.mem.Allocator) !Self {
    const compute_shader = try g.device.create_shader_module_wgsl_from_file("compute shader", "shaders/compute.wgsl", alloc);
    errdefer compute_shader.deinit();

    const visualisation_shader = try g.device.create_shader_module_wgsl_from_file("visualisation shader", "shaders/visualiser.wgsl", alloc);
    errdefer visualisation_shader.deinit();

    const target_sidelength: usize = 128;
    const grid_dimensions: [3]usize = .{target_sidelength / Brickmap.Traits.side_length} ** 3;
    var map = try Map.init(alloc, g.device, .{
        .no_brickmaps = grid_dimensions[0] * grid_dimensions[1] * grid_dimensions[2],
        .grid_dimensions = grid_dimensions,
    });
    errdefer map.deinit();

    const uniform_buffer = try g.device.create_buffer(wgpu.Buffer.Descriptor{
        .label = "uniform buffer",
        .usage = .{
            .uniform = true,
            .copy_dst = true,
        },
        .size = @sizeOf(Uniforms),
    });
    errdefer uniform_buffer.deinit();

    const visualisation_texture_sampler = try g.device.create_sampler(.{
        .label = "visualisation texture sampler",
    });
    errdefer visualisation_texture_sampler.deinit();

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
        .bind_group_layouts = &.{ uniform_bgl, compute_textures_bgl, map.map_bgl },
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

    const visualisation_texture_bgl = try g.device.create_bind_group_layout(wgpu.BindGroupLayout.Descriptor{
        .label = "visualisation texture('s|s') fragment BGL",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .fragment = true },
                .layout = .{ .Sampler = .{ .type = .Filtering } },
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 1,
                .visibility = .{ .fragment = true },
                .layout = .{ .Texture = .{
                    .view_dimension = .D2,
                    .sample_type = .Float,
                } },
            },
        },
    });
    errdefer visualisation_texture_bgl.deinit();

    const visualisation_pipeline_layout = try g.device.create_pipeline_layout(wgpu.PipelineLayout.Descriptor{
        .label = "visualisation pipeline layout",
        .bind_group_layouts = &.{ uniform_bgl, visualisation_texture_bgl },
    });
    errdefer visualisation_pipeline_layout.deinit();

    const visualisation_pipeline = try g.device.create_render_pipeline(wgpu.RenderPipeline.Descriptor{
        .label = "visualisation pipeline",
        .layout = visualisation_pipeline_layout,
        .vertex = .{
            .module = visualisation_shader,
            .entry_point = "vs_main",
            .buffers = &.{},
        },
        .fragment = .{
            .module = visualisation_shader,
            .entry_point = "fs_main",
            .targets = &.{
                .{
                    .format = .BGRA8Unorm,
                    .write_mask = .{
                        .red = true,
                        .green = true,
                        .blue = true,
                        .alpha = true,
                    },
                },
            },
        },
        .primitive = .{
            .topology = .TriangleList,
        },
    });
    errdefer visualisation_pipeline.deinit();

    var ret: Self = .{
        .compute_shader = compute_shader,
        .visualisation_shader = visualisation_shader,

        .uniform_bgl = uniform_bgl,
        .uniform_bg = uniform_bg,
        .uniform_buffer = uniform_buffer,

        .visualisation_texture_bgl = visualisation_texture_bgl,
        .visualisation_texture_bg = .{},
        .visualisation_texture_sampler = visualisation_texture_sampler,
        .visualisation_texture = .{},

        .visualisation_pipeline_layout = visualisation_pipeline_layout,
        .visualisation_pipeline = visualisation_pipeline,

        .map = map,

        .compute_textures_bgl = compute_textures_bgl,
        .compute_textures_bg = .{},

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,
    };
    errdefer ret.deinit();

    try ret.on_resize(@TypeOf(g.*).default_resolution);

    return ret;
}

pub fn deinit(self: *Self) void {
    self.compute_pipeline.deinit();
    self.compute_pipeline_layout.deinit();

    self.compute_textures_bg.deinit();
    self.compute_textures_bgl.deinit();

    self.map.deinit();

    self.visualisation_pipeline.deinit();
    self.visualisation_pipeline_layout.deinit();
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn on_resize(self: *Self, dims: [2]usize) !void {
    self.uniforms.dims = .{
        @floatFromInt(dims[0]),
        @floatFromInt(dims[1]),
    };

    const visualisation_texture = try TextureAndView.init(g.device, .{
        .label = "visualisation texture",
        .usage = .{ .texture_binding = true, .storage_binding = true },
        .dimension = .D2,
        .size = .{
            .width = @intCast(dims[0]),
            .height = @intCast(dims[1]),
            .depth_or_array_layers = 1,
        },
        .format = .BGRA8Unorm,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{ .BGRA8Unorm, .BGRA8UnormSrgb },
    }, null);
    errdefer visualisation_texture.deinit();

    const visualisation_texture_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "visualisation texture('s|s') fragment BGL",
        .layout = self.visualisation_texture_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .Sampler = self.visualisation_texture_sampler },
            },
            wgpu.BindGroup.Entry{
                .binding = 1,
                .resource = .{ .TextureView = visualisation_texture.view },
            },
        },
    });
    errdefer visualisation_texture_bg.deinit();

    const compute_textures_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "compute textures' BG",
        .layout = self.compute_textures_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .TextureView = visualisation_texture.view },
            },
        },
    });
    errdefer compute_textures_bg.deinit();

    self.visualisation_texture.deinit();
    self.visualisation_texture = visualisation_texture;

    self.visualisation_texture_bg.deinit();
    self.visualisation_texture_bg = visualisation_texture_bg;

    self.compute_textures_bg.deinit();
    self.compute_textures_bg = compute_textures_bg;
}

pub fn on_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    _ = self;
    _ = ev;
}

pub fn do_gui(self: *Self) !void {
    if (imgui.begin("asd", null, .{})) {
        _ = imgui.button("asdf", null);

        _ = imgui.input_scalar(u32, "debug mode", &self.uniforms.debug_mode, 1, 1);

        var debug_level: c_int = @intCast(self.uniforms.debug_level);
        if (imgui.c.igInputInt("debug level", &debug_level, 1, 1, 0)) {
            self.uniforms.debug_level = @intCast(debug_level);
        }
    }
    imgui.end();
}

pub fn render(self: *Self, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    try self.map.before_render(g.queue);

    const dims = g.window.get_size() catch @panic("g.window.get_size()");
    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&self.uniforms));

    {
        const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
            .label = "compute pass",
        });

        compute_pass.set_pipeline(self.compute_pipeline);
        compute_pass.set_bind_group(0, self.uniform_bg, null);
        compute_pass.set_bind_group(1, self.compute_textures_bg, null);
        compute_pass.set_bind_group(2, self.map.map_bg, null);

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

    {
        const render_pass = try encoder.begin_render_pass(wgpu.RenderPass.Descriptor{
            .label = "render pass",
            .color_attachments = &.{
                wgpu.RenderPass.ColorAttachment{
                    .view = onto,
                    .load_op = .Load,
                    .store_op = .Store,
                },
            },
        });

        render_pass.set_pipeline(self.visualisation_pipeline);
        render_pass.set_bind_group(0, self.uniform_bg, null);
        render_pass.set_bind_group(1, self.visualisation_texture_bg, null);
        render_pass.draw(.{
            .first_vertex = 0,
            .vertex_count = 6,
            .first_instance = 0,
            .instance_count = 1,
        });
        render_pass.end();
        render_pass.deinit();
    }
}
