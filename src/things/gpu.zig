const std = @import("std");

const blas = @import("blas");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../thing.zig").AnyThing;

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

const Uniforms = extern struct {
    dims: [2]u32,
    _padding_0: [2]u32 = undefined,
    pos: [3]f32,
    _padding_1: [1]f32 = undefined,
    look: [3]f32,
    _padding_2: [1]f32 = undefined,
};

const BufferArray = struct {
    buffers: []wgpu.Buffer = &.{},

    pub fn init(n: usize, device: wgpu.Device, desc: wgpu.Buffer.Descriptor, alloc: std.mem.Allocator) !BufferArray {
        const buffers = try alloc.alloc(wgpu.Buffer, n);
        errdefer alloc.free(buffers);

        var buffers_created: usize = 0;
        errdefer for (0..buffers_created) |i| {
            buffers[i].deinit();
        };

        for (0..n) |i| {
            const buffer = try device.create_buffer(desc);
            errdefer buffer.deinit();

            buffers[i] = buffer;

            buffers_created += 1;
        }

        return .{
            .buffers = buffers,
        };
    }

    pub fn deinit(self: BufferArray, alloc: std.mem.Allocator) void {
        for (self.buffers) |buffer| buffer.deinit();

        alloc.free(self.buffers);
    }
};

const TVArray = struct {
    textures: []wgpu.Texture = &.{},
    views: []wgpu.TextureView = &.{},

    pub fn init(n: usize, device: wgpu.Device, tex_desc: wgpu.Texture.Descriptor, view_desc: ?wgpu.TextureView.Descriptor, alloc: std.mem.Allocator) !TVArray {
        const textures = try alloc.alloc(wgpu.Texture, n);
        errdefer alloc.free(textures);

        const views = try alloc.alloc(wgpu.TextureView, n);
        errdefer alloc.free(views);

        var tvs_created: usize = 0;
        errdefer for (0..tvs_created) |i| {
            views[i].deinit();
            textures[i].deinit();
        };

        for (0..n) |i| {
            const texture = try device.create_texture(tex_desc);
            errdefer texture.deinit();

            const view = try texture.create_view(view_desc);
            errdefer view.deinit();

            textures[i] = texture;
            views[i] = view;

            tvs_created += 1;
        }

        return .{
            .textures = textures,
            .views = views,
        };
    }

    pub fn deinit(self: TVArray, alloc: std.mem.Allocator) void {
        for (self.views) |view| view.deinit();
        for (self.textures) |texture| texture.deinit();

        alloc.free(self.views);
        alloc.free(self.textures);
    }
};

const TextureAndView = struct {
    texture: wgpu.Texture = .{},
    view: wgpu.TextureView = .{},

    pub fn init(device: wgpu.Device, tex_desc: wgpu.Texture.Descriptor, view_desc: ?wgpu.TextureView.Descriptor) !TextureAndView {
        const texture = try device.create_texture(tex_desc);
        errdefer texture.deinit();

        const view = try texture.create_view(view_desc);
        errdefer view.deinit();

        return .{
            .texture = texture,
            .view = view,
        };
    }

    pub fn deinit(self: TextureAndView) void {
        self.texture.deinit();
        self.view.deinit();
    }
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

uniform_buffer: wgpu.Buffer,
uniform_bg: wgpu.BindGroup,

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
bricktree_buffers: BufferArray = .{},
brickmap_textures: TVArray = .{},
brickgrid_texture: TextureAndView = .{},

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

// render_pipeline_layout: wgpu.PipelineLayout,
// render_pipeline: wgpu.RenderPipeline,

pub fn init(alloc: std.mem.Allocator) !Self {
    const compute_shader = try g.device.create_shader_module_wgsl_from_file("compute shader", "shaders/compute.wgsl", alloc);
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

    const compute_pipeline_layout = try g.device.create_pipeline_layout(wgpu.PipelineLayout.Descriptor{
        .label = "compute pipeline layout",
        .bind_group_layouts = &.{ uniform_bgl, map_bgl },
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

    return .{
        .uniform_buffer = uniform_buffer,
        .uniform_bg = uniform_bg,

        .map_bgl = map_bgl,
        .map_bg = map_bg,
        .bricktree_buffers = bricktree_buffers,
        .brickmap_textures = brickmap_textures,
        .brickgrid_texture = brickgrid_texture,

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn on_resize(self: *Self, dims: blas.Vec2uz) !void {
    _ = self;
    _ = dims;
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
    _ = onto;

    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&Uniforms{
        .dims = .{ 1280, 720 },
        .pos = .{ 0.0, 0.0, 0.0 },
        .look = .{ 0.0, 0.0, 0.0 },
    }));

    const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
        .label = "compute pass",
    });
    defer compute_pass.deinit();

    compute_pass.set_pipeline(self.compute_pipeline);
    compute_pass.set_bind_group(0, self.uniform_bg, null);
    compute_pass.set_bind_group(1, self.map_bg, null);
    compute_pass.dispatch_workgroups(.{ 0, 0, 0 });
    compute_pass.end();
}
