const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../thing.zig").AnyThing;

const g = &@import("../main.zig").g;

const BufferArray = @import("gpu/BufferArray.zig");
const TextureAndView = @import("gpu/TextureAndView.zig");
const TVArray = @import("gpu/TVArray.zig");

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

    pub fn on_resize(self_arg: *anyopaque, dims: blas.Vec2uz) anyerror!void {
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

// Be careful: the vecN<T> of WGSL and the [N]T of C/Zig don't have the same alignment!
const Uniforms = extern struct {
    dims: [2]f32,
    _padding_0: [2]u32 = undefined,
    pos: [3]f32,
    _padding_1: [1]f32 = undefined,
    look: [3]f32,
    _padding_2: [1]f32 = undefined,
};

const Brickmap = @import("../brick/map.zig").U8Map(5);

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

const brickmap_buffer_desc = wgpu.Buffer.Descriptor{
    .label = "some bricktree texture",
    .size = (Brickmap.Traits.no_tree_bits / 8 + 3) / 4 * 4,
    .usage = .{
        .copy_dst = true,
        .storage = true,
    },
    .mapped_at_creation = false,
};

const grid_dimensions: [3]usize = .{ 11, 4, 11 };
const no_brickmaps: usize = grid_dimensions[0] * grid_dimensions[1] * grid_dimensions[2];

compute_shader: wgpu.ShaderModule,
visualisation_shader: wgpu.ShaderModule,

uniform_buffer: wgpu.Buffer,
uniform_bgl: wgpu.BindGroupLayout,
uniform_bg: wgpu.BindGroup,

visualisation_texture_bgl: wgpu.BindGroupLayout,
visualisation_texture_bg: wgpu.BindGroup,
visualisation_texture_sampler: wgpu.Sampler,
visualisation_texture: TextureAndView,

visualisation_pipeline_layout: wgpu.PipelineLayout,
visualisation_pipeline: wgpu.RenderPipeline,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
bricktree_buffers: BufferArray,
brickmap_textures: TVArray,
brickgrid_texture: TextureAndView,

compute_textures_bgl: wgpu.BindGroupLayout,
compute_textures_bg: wgpu.BindGroup,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

pub fn init(alloc: std.mem.Allocator) !Self {
    const compute_shader = try g.device.create_shader_module_wgsl_from_file("compute shader", "shaders/compute.wgsl", alloc);
    errdefer compute_shader.deinit();

    const visualisation_shader = try g.device.create_shader_module_wgsl_from_file("visualisation shader", "shaders/visualiser.wgsl", alloc);
    errdefer visualisation_shader.deinit();

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

    const bricktree_buffers = try BufferArray.init(no_brickmaps, g.device, brickmap_buffer_desc, alloc);
    errdefer bricktree_buffers.deinit(alloc);

    const brickmap_textures = try TVArray.init(no_brickmaps, g.device, brickmap_texture_desc, null, alloc);
    errdefer brickmap_textures.deinit(alloc);

    const brickgrid_texture = try TextureAndView.init(g.device, wgpu.Texture.Descriptor{
        .label = "brickgrid texture",
        .size = .{
            .width = grid_dimensions[0],
            .height = grid_dimensions[1],
            .depth_or_array_layers = grid_dimensions[2],
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
    }, null);
    errdefer brickgrid_texture.deinit();

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
                    .min_binding_size = Brickmap.Traits.no_tree_bits / 8,
                } },
                .count = no_brickmaps,
            },
            wgpu.BindGroupLayout.Entry{
                .binding = 2,
                .visibility = .{ .compute = true },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D3,
                } },
                .count = no_brickmaps,
            },
        },
    });
    errdefer map_bgl.deinit();

    const map_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "grid bg",
        .layout = map_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .TextureView = brickgrid_texture.view },
            },
            wgpu.BindGroup.Entry{
                .binding = 1,
                .resource = .{ .BufferArray = bricktree_buffers.buffers },
            },
            wgpu.BindGroup.Entry{
                .binding = 2,
                .resource = .{ .TextureViewArray = brickmap_textures.views },
            },
        },
    });
    errdefer map_bg.deinit();

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

        .map_bgl = map_bgl,
        .map_bg = map_bg,
        .bricktree_buffers = bricktree_buffers,
        .brickmap_textures = brickmap_textures,
        .brickgrid_texture = brickgrid_texture,

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
    _ = self;
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn on_resize(self: *Self, dims: blas.Vec2uz) !void {
    const visualisation_texture = try TextureAndView.init(g.device, .{
        .label = "visualisation texture",
        .usage = .{ .texture_binding = true, .storage_binding = true },
        .dimension = .D2,
        .size = .{
            .width = @intCast(dims.x()),
            .height = @intCast(dims.y()),
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
    _ = self;

    _ = imgui.c.igBegin("asd", null, 0);
    defer imgui.c.igEnd();

    _ = imgui.c.igButton("asdf", .{ .x = 0, .y = 0 });
}

pub fn render(self: *Self, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    const dims = g.window.get_size() catch @panic("g.window.get_size()");
    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&Uniforms{
        .dims = .{
            @floatFromInt(dims.x()),
            @floatFromInt(dims.y()),
        },
        .pos = .{ 0.0, 0.0, 0.0 },
        .look = .{ 0.0, 0.0, 0.0 },
    }));

    const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
        .label = "compute pass",
    });

    compute_pass.set_pipeline(self.compute_pipeline);
    compute_pass.set_bind_group(0, self.uniform_bg, null);
    compute_pass.set_bind_group(1, self.compute_textures_bg, null);
    compute_pass.set_bind_group(2, self.map_bg, null);

    const wg_sz = blas.vec2uz(8, 8);
    const wg_count = blas.divew(
        blas.sub(
            blas.add(dims, wg_sz),
            blas.vec2uz(1, 1),
        ),
        wg_sz,
    );
    compute_pass.dispatch_workgroups(.{
        @intCast(wg_count.width()),
        @intCast(wg_count.height()),
        1,
    });

    compute_pass.end();
    compute_pass.deinit();

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
