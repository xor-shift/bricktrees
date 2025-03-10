const std = @import("std");

const mustache = @import("mustache");

const wgpu = @import("gfx").wgpu;

const wgm = @import("wgm");
const imgui = @import("imgui");

const CameraThing = @import("../../../things/CameraThing.zig");
const VisualiserThing = @import("../../../things/VisualiserThing.zig");

const g = &@import("../../../main.zig").g;

fn make_shader(alloc: std.mem.Allocator, comptime Cfg: type) !wgpu.ShaderModule {
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
    try mustache.render(res, Cfg.to_mustache(), out.writer());
    defer out.deinit();

    //

    const shader_code = try out.toOwnedSliceSentinel(0);
    defer alloc.free(shader_code);

    const shader = try g.device.create_shader_module_wgsl("compute shader", shader_code);

    return shader;
}

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

pub fn Computer(comptime Cfg: type) type {
    return struct {
        const Self = @This();

        const Backend = @import("../backend.zig").Backend(Cfg);
        const Painter = @import("painter.zig").Painter(Cfg);
        const Storage = @import("storage.zig").Storage(Cfg);

        backend: *Backend = undefined,
        painter: *Painter = undefined,
        storage: *Storage = undefined,

        compute_shader: wgpu.ShaderModule,
        scratch_reset_shader: wgpu.ShaderModule,

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
        scratch_reset_pipeline: wgpu.ComputePipeline,

        pub fn init(map_bgl: wgpu.BindGroupLayout) !Self {
            const scratch_reset_shader_code: [:0]const u8 =
                \\ @group(2) @binding(0)
                \\ var brickgrid: texture_3d<u32>;
                \\ @group(2) @binding(2)
                \\ var<storage, read_write> feedback_scratch: array<u32>;
                \\
                \\ @compute
                \\ @workgroup_size(4, 4, 4)
                \\ fn cs_main(
                \\     @builtin(global_invocation_id) global_id: vec3<u32>,
                \\ ) {
                \\     let brickgrid_dims = textureDimensions(brickgrid);
                \\     let idx =
                \\         global_id.x +
                \\         global_id.y * brickgrid_dims.x +
                \\         global_id.z * brickgrid_dims.x * brickgrid_dims.y;
                \\     feedback_scratch[idx] = 0u;
                \\ }
            ;

            const scratch_reset_shader = try g.device.create_shader_module_wgsl("scratch reset shader", scratch_reset_shader_code);
            errdefer scratch_reset_shader.deinit();

            const compute_shader = try make_shader(g.alloc, Cfg);
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

            const scratch_reset_pipeline = try g.device.create_compute_pipeline(.{
                .label = "scratch reset pipeline",
                .layout = compute_pipeline_layout,
                .compute = .{
                    .module = scratch_reset_shader,
                    .entry_point = "cs_main",
                    .constants = &.{},
                },
            });
            errdefer scratch_reset_pipeline.deinit();

            var ret: Self = .{
                .compute_shader = compute_shader,
                .scratch_reset_shader = scratch_reset_shader,

                .uniform_bgl = uniform_bgl,
                .uniform_bg = uniform_bg,
                .uniform_buffer = uniform_buffer,
                .rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64)),

                .compute_textures_bgl = compute_textures_bgl,
                .compute_textures_bg = .{},

                .compute_pipeline_layout = compute_pipeline_layout,
                .compute_pipeline = compute_pipeline,
                .scratch_reset_pipeline = scratch_reset_pipeline,
            };
            errdefer ret.deinit();

            try ret.resize(try g.window.get_size());

            return ret;
        }

        pub fn deinit(self: *Self) void {
            _ = self;
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

        pub fn do_gui(self: *Self) void {
            if (imgui.begin("asd", null, .{})) {
                _ = imgui.button("asdf", null);

                _ = imgui.input_scalar(u32, "debug mode", &self.uniforms.debug_mode, 1, 1);
                _ = imgui.input_scalar(u32, "debug level", &self.uniforms.debug_level, 1, 1);
                _ = imgui.input_scalar(u32, "debug variable 0", &self.uniforms.debug_variable_0, 1, 1);
                _ = imgui.input_scalar(u32, "debug variable 1", &self.uniforms.debug_variable_1, 1, 1);
            }
            imgui.end();
        }

        pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
            const dims = g.window.get_size() catch @panic("g.window.get_size()");

            const camera = g.get_thing("camera").?.get_concrete(CameraThing);

            self.rand.fill(std.mem.asBytes(&self.uniforms.random_seed));
            self.uniforms.transform = wgm.lossy_cast(f32, camera.cached_transform);
            self.uniforms.inverse_transform = wgm.lossy_cast(f32, camera.cached_transform_inverse);

            g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&self.uniforms));

            {
                const scratch_reset_pass = try encoder.begin_compute_pass(.{
                    .label = "scratch reset pass",
                });
                defer scratch_reset_pass.deinit();

                scratch_reset_pass.set_pipeline(self.scratch_reset_pipeline);
                scratch_reset_pass.set_bind_group(0, self.uniform_bg, null);
                scratch_reset_pass.set_bind_group(1, self.compute_textures_bg, null);
                scratch_reset_pass.set_bind_group(2, self.backend.map_bg, null);

                const gd = wgm.cast(u32, self.backend.config.?.grid_dimensions).?;
                const wg_sz = [_]u32{4} ** 3;
                const wg_ct = .{
                    (gd[0] + wg_sz[0] - 1) / wg_sz[0],
                    (gd[1] + wg_sz[1] - 1) / wg_sz[1],
                    (gd[2] + wg_sz[2] - 1) / wg_sz[2],
                };
                // std.log.debug("{any}, {d}", .{wg_ct, gs});
                scratch_reset_pass.dispatch_workgroups(wg_ct);

                scratch_reset_pass.end();
            }

            {
                const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
                    .label = "compute pass",
                });
                defer compute_pass.deinit();

                compute_pass.set_pipeline(self.compute_pipeline);
                compute_pass.set_bind_group(0, self.uniform_bg, null);
                compute_pass.set_bind_group(1, self.compute_textures_bg, null);
                compute_pass.set_bind_group(2, self.backend.map_bg, null);

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
            }
        }
    };
}
