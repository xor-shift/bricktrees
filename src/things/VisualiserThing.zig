const std = @import("std");

const dyn = @import("dyn");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const IThing = @import("../IThing.zig");

const TextureAndView = @import("gpu/TextureAndView.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const DynStatic = dyn.ConcreteStuff(@This(), .{IThing});

shader: wgpu.ShaderModule,

visualisation_texture_bgl: wgpu.BindGroupLayout,
visualisation_texture_bg: wgpu.BindGroup = .{},
visualisation_texture_sampler: wgpu.Sampler,
visualisation_texture: TextureAndView = .{},

visualisation_pipeline_layout: wgpu.PipelineLayout,
visualisation_pipeline: wgpu.RenderPipeline,

pub fn init() !Self {
    const visualisation_shader = try g.device.create_shader_module_wgsl_from_file("visualisation shader", "shaders/visualiser.wgsl", g.alloc);
    errdefer visualisation_shader.deinit();

    const visualisation_texture_sampler = try g.device.create_sampler(.{
        .label = "visualisation texture sampler",
    });
    errdefer visualisation_texture_sampler.deinit();

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
        .bind_group_layouts = &.{visualisation_texture_bgl},
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
        .shader = visualisation_shader,

        .visualisation_texture_bgl = visualisation_texture_bgl,
        .visualisation_texture_bg = .{},
        .visualisation_texture_sampler = visualisation_texture_sampler,
        .visualisation_texture = .{},

        .visualisation_pipeline_layout = visualisation_pipeline_layout,
        .visualisation_pipeline = visualisation_pipeline,
    };

    try ret.resize(@TypeOf(g.*).default_resolution);

    return ret;
}

pub fn deinit(self: *Self) void {
    self.visualisation_pipeline.deinit();
    self.visualisation_pipeline_layout.deinit();

    self.visualisation_texture_bgl.deinit();
    self.visualisation_texture_bg.deinit();
    self.visualisation_texture_sampler.deinit();
    self.visualisation_texture.deinit();

    self.shader.deinit();
}

/// From IThing
pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

/// From IThing
pub fn resize(self: *Self, dims: [2]usize) !void {
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

    self.visualisation_texture.deinit();
    self.visualisation_texture = visualisation_texture;

    self.visualisation_texture_bg.deinit();
    self.visualisation_texture_bg = visualisation_texture_bg;
}

/// From IThing
pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
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
    render_pass.set_bind_group(0, self.visualisation_texture_bg, null);
    render_pass.draw(.{
        .first_vertex = 0,
        .vertex_count = 6,
        .first_instance = 0,
        .instance_count = 1,
    });
    render_pass.end();
    render_pass.deinit();
}
