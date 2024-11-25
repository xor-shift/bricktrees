const std = @import("std");
const future = @import("future.zig");
const blas = @import("blas/blas.zig");

pub const sdl = @import("sdl.zig");
pub const wgpu = @import("wgpu/wgpu.zig");

const Map = @import("map.zig");
const NewUniforms = @import("uniforms.zig");
const State = @import("state.zig");

const Vertex = extern struct {
    pos: [3]f32,
    uv: [2]f32,

    fn describe() wgpu.VertexBufferLayout {
        comptime std.debug.assert(@sizeOf(Vertex) == @sizeOf(f32) * 5);
        comptime std.debug.assert(@alignOf(Vertex) == @alignOf(f32));

        return .{
            .array_stride = @intCast(@sizeOf(Vertex)),
            .step_mode = .Vertex,
            .attributes = &.{
                .{
                    .format = .Float32x3,
                    .offset = 0,
                    .shader_location = 0,
                },
                .{
                    .format = .Float32x2,
                    .offset = @sizeOf([3]f32),
                    .shader_location = 1,
                },
            },
        };
    }
};

pub var g_state: State = undefined;

const TextureSet = struct {
    visualisation: wgpu.Texture,
    view_visualisation: wgpu.TextureView,
};

const UniformStuff = struct {
    bgl_uniform: wgpu.BindGroupLayout,
    bg_uniform: wgpu.BindGroup,
    buffer: wgpu.Buffer,

    fn init() !UniformStuff {
        const bgl_uniform = try g_state.device.create_bind_group_layout(.{
            .label = "test bgl 0",
            .entries = &.{
                .{
                    .binding = 0,
                    .visibility = .{
                        .vertex = true,
                        .fragment = true,
                        .compute = true,
                    },
                    .layout = .{ .Buffer = .{
                        .type = .Uniform,
                    } },
                },
            },
        });

        const buffer = try g_state.device.create_buffer(.{
            .label = "uniform buffer",
            .usage = .{
                .copy_dst = true,
                .uniform = true,
            },
            .size = @sizeOf(NewUniforms.Serialized),
        });
        std.log.debug("buffer: {?p}", .{buffer.handle});

        const bg_uniform = try g_state.device.create_bind_group(.{
            .label = "test bg",
            .layout = bgl_uniform,
            .entries = &.{.{
                .binding = 0,
                .resource = .{ .Buffer = .{
                    .buffer = buffer,
                    .offset = 0,
                    .size = @sizeOf(NewUniforms.Serialized),
                } },
            }},
        });

        return .{
            .bgl_uniform = bgl_uniform,
            .bg_uniform = bg_uniform,
            .buffer = buffer,
        };
    }
};

const Computer = struct {
    shader: wgpu.ShaderModule,

    pipeline_layout: wgpu.PipelineLayout,
    pipeline: wgpu.ComputePipeline,

    geometry_bgl: wgpu.BindGroupLayout,
    geometry_bg: wgpu.BindGroup = .{},

    geometry_textures: [2]wgpu.Texture = .{ .{}, .{} },
    geometry_texture_views: [2]wgpu.TextureView = .{ .{}, .{} },
    radiance_texture: wgpu.Texture = .{},
    radiance_texture_view: wgpu.TextureView = .{},

    fn init(uniform_stuff: UniformStuff, map: Map, alloc: std.mem.Allocator) !Computer {
        const shader = try g_state.device.create_shader_module_wgsl_from_file("compute shader", "src/compute.wgsl", alloc);

        const geometry_bgl = try g_state.device.create_bind_group_layout(.{
            .label = "compute geometry bgl",
            .entries = &.{
                .{
                    .binding = 0,
                    .visibility = .{
                        .compute = true,
                    },
                    .layout = .{ .StorageTexture = .{
                        .access = .WriteOnly,
                        .format = .RGBA32Uint,
                        .view_dimension = .D2,
                    } },
                },
                .{
                    .binding = 1,
                    .visibility = .{
                        .compute = true,
                    },
                    .layout = .{ .StorageTexture = .{
                        .access = .WriteOnly,
                        .format = .RGBA32Uint,
                        .view_dimension = .D2,
                    } },
                },
                .{
                    .binding = 2,
                    .visibility = .{
                        .compute = true,
                    },
                    .layout = .{ .StorageTexture = .{
                        .access = .WriteOnly,
                        .format = .RGBA8Unorm,
                        .view_dimension = .D2,
                    } },
                },
            },
        });

        const pipeline_layout = try g_state.device.create_pipeline_layout(.{
            .label = "visualiser pipeline layout",
            .bind_group_layouts = &.{ uniform_stuff.bgl_uniform, geometry_bgl, map.map_bgl },
        });
        std.log.debug("compute pipeline_layout: {?p}", .{pipeline_layout.handle});

        const pipeline = try g_state.device.create_compute_pipeline(.{ .label = "compute pipeline", .layout = pipeline_layout, .compute = .{
            .module = shader,
            .entry_point = "cs_main",
            .constants = &.{},
        } });
        std.log.debug("compute pipeline: {?p}", .{pipeline.handle});

        var ret: Computer = .{
            .shader = shader,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .geometry_bgl = geometry_bgl,
        };

        try ret.resize(try g_state.window.get_size());

        return ret;
    }

    fn resize(self: *Computer, dims: blas.Vec2uz) !void {
        for (0..2) |i| {
            if (self.geometry_textures[i].handle != null) self.geometry_textures[i].release();
            self.geometry_textures[i] = try g_state.device.create_texture(.{
                .label = "a geometry texture",
                .usage = .{
                    .copy_src = true,
                    .texture_binding = true,
                    .storage_binding = true,
                },
                .dimension = .D2,
                .size = .{
                    .width = @intCast(dims.width()),
                    .height = @intCast(dims.height()),
                    .depth_or_array_layers = 1,
                },
                .format = .RGBA32Uint,
                .mipLevelCount = 1,
                .sampleCount = 1,
                .view_formats = &.{},
            });
            std.log.debug("compute geometry texture #{d}: {any}", .{ i, self.geometry_textures[i] });

            if (self.geometry_texture_views[i].handle != null) self.geometry_texture_views[i].release();
            self.geometry_texture_views[i] = try self.geometry_textures[0].create_view(null);
            std.log.debug("compute geometry texture view #{d}: {any}", .{ i, self.geometry_texture_views[i] });
        }

        if (self.radiance_texture.handle != null) self.radiance_texture.release();
        self.radiance_texture = try g_state.device.create_texture(.{
            .label = "radiance texture",
            .usage = .{
                .copy_src = true,
                .texture_binding = true,
                .storage_binding = true,
            },
            .dimension = .D2,
            .size = .{
                .width = @intCast(dims.width()),
                .height = @intCast(dims.height()),
                .depth_or_array_layers = 1,
            },
            .format = .RGBA8Unorm,
            .mipLevelCount = 1,
            .sampleCount = 1,
            .view_formats = &.{},
        });
        std.log.debug("compute radiance texture: {any}", .{self.radiance_texture});

        self.radiance_texture_view = try self.radiance_texture.create_view(null);
        std.log.debug("compute radiance texture view: {any}", .{self.radiance_texture_view});

        self.geometry_bg = try g_state.device.create_bind_group(.{
            .label = "compute bind group",
            .layout = self.geometry_bgl,
            .entries = &.{
                .{
                    .binding = 0,
                    .resource = .{ .TextureView = self.geometry_texture_views[0] },
                },
                .{
                    .binding = 1,
                    .resource = .{ .TextureView = self.geometry_texture_views[1] },
                },
                .{
                    .binding = 2,
                    .resource = .{ .TextureView = self.radiance_texture_view },
                },
            },
        });
    }

    fn render(self: Computer, uniform_stuff: UniformStuff, map: Map, encoder: wgpu.CommandEncoder, target: wgpu.TextureView) !void {
        _ = target;

        const compute_pass = try encoder.begin_compute_pass(.{
            .label = "compute pass",
        });

        compute_pass.set_pipeline(self.pipeline);
        compute_pass.set_bind_group(0, uniform_stuff.bg_uniform, null);
        compute_pass.set_bind_group(1, self.geometry_bg, null);
        compute_pass.set_bind_group(2, map.map_bg, null);

        const dims = try g_state.window.get_size();
        const wg_sz = blas.vec2uz(8, 8);
        const wg_count = blas.divew(blas.sub(blas.add(dims, wg_sz), blas.vec2uz(1, 1)), wg_sz);
        compute_pass.dispatch_workgroups(.{ @intCast(wg_count.width()), @intCast(wg_count.height()), 1 });

        compute_pass.end();
        compute_pass.release();
    }
};

const Visualiser = struct {
    shader: wgpu.ShaderModule,

    render_pipeline_layout: wgpu.PipelineLayout,
    render_pipeline: wgpu.RenderPipeline,

    computer: *Computer,

    texture_bgl: wgpu.BindGroupLayout,
    texture_bg: wgpu.BindGroup = .{},
    sampler: wgpu.Sampler,

    vertex_buffer: wgpu.Buffer,

    fn init(uniform_stuff: UniformStuff, computer: *Computer, alloc: std.mem.Allocator) !Visualiser {
        const shader = try g_state.device.create_shader_module_wgsl_from_file("visualiser shader", "src/main.wgsl", alloc);

        const bgl_textures = try g_state.device.create_bind_group_layout(.{
            .label = "textures' bgl",
            .entries = &.{
                .{
                    .binding = 0,
                    .visibility = .{
                        .fragment = true,
                    },
                    .layout = .{ .Sampler = .{ .type = .NonFiltering } },
                },
                .{
                    .binding = 1,
                    .visibility = .{
                        .fragment = true,
                    },
                    .layout = .{ .Texture = .{
                        .sample_type = .Float,
                        .view_dimension = .D2,
                        .multisampled = false,
                    } },
                },
                .{
                    .binding = 2,
                    .visibility = .{
                        .fragment = true,
                    },
                    .layout = .{ .Texture = .{
                        .sample_type = .Uint,
                        .view_dimension = .D2,
                        .multisampled = false,
                    } },
                },
                .{
                    .binding = 3,
                    .visibility = .{
                        .fragment = true,
                    },
                    .layout = .{ .Texture = .{
                        .sample_type = .Uint,
                        .view_dimension = .D2,
                        .multisampled = false,
                    } },
                },
            },
        });

        const pipeline_layout = try g_state.device.create_pipeline_layout(.{
            .label = "visualiser pipeline layout",
            .bind_group_layouts = &.{ uniform_stuff.bgl_uniform, bgl_textures },
        });
        std.log.debug("visualiser pipeline_layout: {?p}", .{pipeline_layout.handle});

        const render_pipeline = try g_state.device.create_render_pipeline(.{
            .label = "visulaiser pipeline",
            .layout = pipeline_layout,
            .vertex = .{
                .module = shader,
                .entry_point = "vs_main",
                .buffers = &.{Vertex.describe()},
            },
            .fragment = .{
                .module = shader,
                .entry_point = "fs_main",
                .targets = &.{.{ .format = .BGRA8Unorm, .write_mask = .{
                    .red = true,
                    .green = true,
                    .blue = true,
                    .alpha = true,
                } }},
            },
            .primitive = .{
                .topology = .TriangleList,
            },
        });
        std.log.debug("visualiser pipeline: {?p}", .{render_pipeline.handle});

        const sampler = try g_state.device.create_sampler(.{});

        const vertex_buffer = try g_state.device.create_buffer(.{
            .label = "vertex buffer",
            .usage = .{
                .copy_dst = true,
                .vertex = true,
            },
            .size = @sizeOf(Vertex) * 6,
        });
        g_state.queue.write_buffer(vertex_buffer, 0, std.mem.sliceAsBytes(&[_]Vertex{
            .{ .pos = .{ -1.0, 1.0, 0.0 }, .uv = .{ 0.0, 0.0 } },
            .{ .pos = .{ -1.0, -1.0, 0.0 }, .uv = .{ 0.0, 1.0 } },
            .{ .pos = .{ 1.0, -1.0, 0.0 }, .uv = .{ 1.0, 1.0 } },
            .{ .pos = .{ 1.0, -1.0, 0.0 }, .uv = .{ 1.0, 1.0 } },
            .{ .pos = .{ 1.0, 1.0, 0.0 }, .uv = .{ 1.0, 0.0 } },
            .{ .pos = .{ -1.0, 1.0, 0.0 }, .uv = .{ 0.0, 0.0 } },
        }));

        var ret: Visualiser = .{
            .shader = shader,

            .render_pipeline_layout = pipeline_layout,
            .render_pipeline = render_pipeline,

            .computer = computer,
            .texture_bgl = bgl_textures,
            .sampler = sampler,

            .vertex_buffer = vertex_buffer,
        };

        try ret.resize(try g_state.window.get_size());

        return ret;
    }

    fn resize(self: *Visualiser, dims: blas.Vec2uz) !void {
        _ = dims;

        if (self.texture_bg.handle != null) {
            self.texture_bg.release();
        }

        const bg_textures = try g_state.device.create_bind_group(.{
            .label = "visualisation textures' bg",
            .layout = self.texture_bgl,
            .entries = &.{
                .{
                    .binding = 0,
                    .resource = .{ .Sampler = self.sampler },
                },
                .{
                    .binding = 1,
                    .resource = .{ .TextureView = self.computer.radiance_texture_view },
                },
                .{
                    .binding = 2,
                    .resource = .{ .TextureView = self.computer.geometry_texture_views[0] },
                },
                .{
                    .binding = 3,
                    .resource = .{ .TextureView = self.computer.geometry_texture_views[1] },
                },
            },
        });

        self.texture_bg = bg_textures;
    }

    fn render(self: Visualiser, uniform_stuff: UniformStuff, encoder: wgpu.CommandEncoder, target: wgpu.TextureView) !void {
        const render_pass = try encoder.begin_render_pass(.{
            .color_attachments = &.{.{
                .view = target,
                .load_op = .Clear,
                .store_op = .Store,
                .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.5, .a = 1.0 },
            }},
        });
        // std.log.debug("render_pass: {p}", .{render_pass.handle.?});

        render_pass.set_pipeline(self.render_pipeline);
        render_pass.set_vertex_buffer(0, self.vertex_buffer, 0, @sizeOf(Vertex) * 6);
        render_pass.set_bind_group(0, uniform_stuff.bg_uniform, null);
        render_pass.set_bind_group(1, self.texture_bg, null);
        render_pass.draw(.{
            .vertex_count = 6,
            .instance_count = 1,
            .first_vertex = 0,
            .first_instance = 0,
        });
        render_pass.end();
        render_pass.release();
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    g_state = try State.init(alloc);
    defer g_state.deinit();

    const map = try Map.init(alloc);
    const uniform_stuff = try UniformStuff.init();
    var computer = try Computer.init(uniform_stuff, map, alloc);
    var visualiser = try Visualiser.init(uniform_stuff, &computer, alloc);

    var uniforms: NewUniforms = .{};
    uniforms.resize(try g_state.window.get_size());

    var frame_timer = try std.time.Timer.start();
    var ms_spent_last_frame: f64 = 1000.0;
    outer: while (true) {
        const inter_frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        g_state.queue.write_buffer(uniform_stuff.buffer, 0, std.mem.asBytes(&uniforms.serialize()));

        while (try sdl.poll_event()) |ev| {
            uniforms.event(ev);

            switch (ev.common.type) {
                sdl.c.SDL_EVENT_QUIT => break :outer,
                sdl.c.SDL_EVENT_WINDOW_RESIZED => {
                    const event = ev.window;
                    const dims = blas.vec2uz(@intCast(event.data1), @intCast(event.data2));

                    uniforms.resize(dims);
                    try g_state.resize(dims);
                    try computer.resize(dims);
                    try visualiser.resize(dims);
                },
                sdl.c.SDL_EVENT_KEY_DOWN => {
                    switch (ev.key.key) {
                        sdl.c.SDLK_Q => break :outer,
                        else => {},
                    }
                },
                sdl.c.SDL_EVENT_MOUSE_MOTION => {},
                sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {},
                else => {
                    // std.log.debug("unknown event", .{});
                },
            }
        }

        uniforms.pre_frame(ms_spent_last_frame);

        const current_texture = g_state.surface.get_current_texture() catch |e| {
            if (e == wgpu.Error.Outdated) {
                std.log.debug("outdated", .{});
                continue;
            } else {
                return e;
            }
        };
        // std.log.debug("current_texture: {p}, (suboptimal: {d})", .{ current_texture.texture.handle.?, @intFromBool(current_texture.suboptimal) });

        const current_texture_view = try current_texture.texture.create_view(.{
            .label = "current render texture view",
        });
        // std.log.debug("current_texture_view: {p}", .{current_texture_view.handle.?});

        const command_encoder = try g_state.device.create_command_encoder(null);
        // std.log.debug("command_encoder: {p}", .{command_encoder.handle.?});

        try computer.render(uniform_stuff, map, command_encoder, current_texture_view);
        try visualiser.render(uniform_stuff, command_encoder, current_texture_view);

        current_texture_view.release();

        const command_buffer = try command_encoder.finish(null);
        command_encoder.release();
        g_state.queue.submit((&command_buffer)[0..1]);
        command_buffer.release();

        g_state.surface.present();

        current_texture.texture.release();

        const frame_time = @as(f64, @floatFromInt(frame_timer.lap())) / @as(f64, @floatFromInt(std.time.ns_per_ms));

        ms_spent_last_frame = frame_time + inter_frame_time;
        // std.log.debug("{d}ms between frames, {d}ms during frame", .{ inter_frame_time, frame_time });
    }
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(blas);
}
