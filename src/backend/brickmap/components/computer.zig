const std = @import("std");

const mustache = @import("mustache");

const wgpu = @import("gfx").wgpu;

const wgm = @import("wgm");
const imgui = @import("imgui");

const CameraThing = @import("../../../things/CameraThing.zig");
const VisualiserThing = @import("../../../things/VisualiserThing.zig");

const Common = @import("../../Common.zig");
const Uniforms = @import("../../uniforms.zig").Uniforms;

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
        feedback_reset_shader: wgpu.ShaderModule,

        common: Common,

        compute_pipeline_layout: wgpu.PipelineLayout,
        compute_pipeline: wgpu.ComputePipeline,
        scratch_reset_pipeline: wgpu.ComputePipeline,
        feedback_reset_pipeline: wgpu.ComputePipeline,

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

            const feedback_reset_shader_code: [:0]const u8 =
                \\ @group(2) @binding(1)
                \\ var<storage, read_write> feedback_buffer: array<u32>;
                \\
                \\ @compute
                \\ @workgroup_size(4, 4, 4)
                \\ fn cs_main(
                \\     @builtin(global_invocation_id) global_id: vec3<u32>,
                \\ ) {
                \\     feedback_buffer[global_id.x] = 0u;
                \\ }
            ;

            const feedback_reset_shader = try g.device.create_shader_module_wgsl("feedback buffer reset shader", feedback_reset_shader_code);
            errdefer feedback_reset_shader.deinit();

            const compute_shader = try make_shader(g.alloc, Cfg);
            errdefer compute_shader.deinit();

            const common = try Common.init();

            const compute_pipeline_layout = try g.device.create_pipeline_layout(wgpu.PipelineLayout.Descriptor{
                .label = "compute pipeline layout",
                .bind_group_layouts = &.{ common.uniform_bgl, common.compute_textures_bgl, map_bgl },
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

            const feedback_reset_pipeline = try g.device.create_compute_pipeline(.{
                .label = "scratch reset pipeline",
                .layout = compute_pipeline_layout,
                .compute = .{
                    .module = feedback_reset_shader,
                    .entry_point = "cs_main",
                    .constants = &.{},
                },
            });
            errdefer feedback_reset_pipeline.deinit();

            var ret: Self = .{
                .compute_shader = compute_shader,
                .scratch_reset_shader = scratch_reset_shader,
                .feedback_reset_shader = feedback_reset_shader,

                .common = common,

                .compute_pipeline_layout = compute_pipeline_layout,
                .compute_pipeline = compute_pipeline,
                .scratch_reset_pipeline = scratch_reset_pipeline,
                .feedback_reset_pipeline = feedback_reset_pipeline,
            };
            errdefer ret.deinit();

            try ret.resize(try g.window.get_size());

            return ret;
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn resize(self: *Self, dims: [2]usize) !void {
            try self.common.resize(dims);
        }

        pub fn do_options_ui(self: *Self) void {
            self.common.do_options_ui();
        }

        pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
            {
                const origin = wgm.cast(i32, self.backend.origin_brickmap).?;
                self.common.uniforms.custom = .{
                    @bitCast(origin[0]),
                    @bitCast(origin[1]),
                    @bitCast(origin[2]),
                    undefined,
                };
            }
            try self.common.render(delta_ns, encoder, onto);

            const dims = g.window.get_size() catch @panic("g.window.get_size()");

            {
                const feedback_reset_pass = try encoder.begin_compute_pass(.{
                    .label = "feedback buffer reset pass",
                });
                defer feedback_reset_pass.deinit();

                feedback_reset_pass.set_pipeline(self.feedback_reset_pipeline);
                feedback_reset_pass.set_bind_group(0, self.common.uniform_bg, null);
                feedback_reset_pass.set_bind_group(1, self.common.compute_textures_bg, null);
                feedback_reset_pass.set_bind_group(2, self.backend.map_bg, null);

                const bytes: u32 = @intCast((self.backend.config.?.feedback_sz + 1) * @sizeOf(u32));
                const wg_sz = 64;
                const wg_ct = .{
                    (bytes + wg_sz - 1) / wg_sz,
                    1,
                    1,
                };
                feedback_reset_pass.dispatch_workgroups(wg_ct);

                feedback_reset_pass.end();
            }

            {
                const scratch_reset_pass = try encoder.begin_compute_pass(.{
                    .label = "scratch reset pass",
                });
                defer scratch_reset_pass.deinit();

                scratch_reset_pass.set_pipeline(self.scratch_reset_pipeline);
                scratch_reset_pass.set_bind_group(0, self.common.uniform_bg, null);
                scratch_reset_pass.set_bind_group(1, self.common.compute_textures_bg, null);
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
                compute_pass.set_bind_group(0, self.common.uniform_bg, null);
                compute_pass.set_bind_group(1, self.common.compute_textures_bg, null);
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
