const std = @import("std");

const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;
const wgm = @import("wgm");

const rt = @import("../rt/ray.zig");

const AnyThing = @import("../AnyThing.zig");
const VoxelProvider = @import("../VoxelProvider.zig");

const CameraThing = @import("CameraThing.zig");

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const Ray = CameraThing.Ray;
const Intersection = Ray.Intersection;

const g = &@import("../main.zig").g;

const Self = @This();

const Uniforms = struct {
    transform: [4][4]f32,
};

const GizmoVertex = extern struct {
    pos: [4]f32,
    color: [4]u8,

    pub fn desc() wgpu.VertexBufferLayout {
        return .{
            .array_stride = @sizeOf(GizmoVertex),
            .step_mode = .Vertex,
            .attributes = &.{
                .{
                    .format = .Float32x4,
                    .offset = 0,
                    .shader_location = 0,
                },
                .{
                    .format = .Unorm8x4,
                    .offset = 16,
                    .shader_location = 1,
                },
            },
        };
    }
};

vtable_thing: AnyThing = AnyThing.mk_vtable(Self),
vtable_voxel_provider: VoxelProvider = VoxelProvider.mk_vtable(Self),

gizmo_pipeline_layout: wgpu.PipelineLayout,
gizmo_pipeline: wgpu.RenderPipeline,
gizmo_vbo: wgpu.Buffer,

gizmo_uniform_bg: wgpu.BindGroup,
gizmo_uniform_buffer: wgpu.Buffer,

origin: [3]isize = .{ 1, 30, 3 },
voxels: []PackedVoxel,

camera: *CameraThing = undefined,

pub fn init() !Self {
    const shader_code = @embedFile("../shaders/gizmo.wgsl");

    const shader_module = try g.device.create_shader_module_wgsl("gizmo sahder", shader_code);
    errdefer shader_module.deinit();

    const gizmo_uniform_bgl = try g.device.create_bind_group_layout(.{
        .label = "gizmo uniform bgl",
        .entries = &.{wgpu.BindGroupLayout.Entry{
            .binding = 0,
            .visibility = .{ .vertex = true },
            .layout = .{ .Buffer = .{ .type = .Uniform } },
        }},
    });

    const gizmo_pipeline_layout = try g.device.create_pipeline_layout(.{
        .label = "editor gizmo pipeline layout",
        .bind_group_layouts = &.{gizmo_uniform_bgl},
    });
    errdefer gizmo_pipeline_layout.deinit();

    const gizmo_pipeline = try g.device.create_render_pipeline(.{
        .label = "editor gizmo pipeline",
        .layout = gizmo_pipeline_layout,
        .vertex = .{
            .module = shader_module,
            .entry_point = "vs_main",
            .buffers = &.{GizmoVertex.desc()},
        },
        .primitive = .{
            .topology = .LineList,
        },
        .fragment = .{
            .module = shader_module,
            .entry_point = "fs_main",
            .targets = &.{.{
                .format = .BGRA8Unorm,
                .blend = wgpu.BlendState.alpha_blending,
                .write_mask = .{
                    .red = true,
                    .green = true,
                    .blue = true,
                    .alpha = true,
                },
            }},
        },
    });
    errdefer gizmo_pipeline.deinit();

    const gizmo_vbo = try g.device.create_buffer(.{
        .label = "editor gizmo vertex buffer",
        .size = 8192,
        .usage = .{
            .vertex = true,
            .copy_dst = true,
            .map_read = true,
        },
    });
    errdefer gizmo_vbo.deinit();

    const gizmo_uniform_buffer = try g.device.create_buffer(.{
        .label = "editor gizmo renderer uniform buffer",
        .size = @sizeOf(Uniforms),
        .usage = .{
            .uniform = true,
            .copy_dst = true,
            .map_read = true,
        },
    });
    errdefer gizmo_uniform_buffer.deinit();

    const gizmo_uniform_bg = try g.device.create_bind_group(.{
        .label = "gizmo uniform bg",
        .layout = gizmo_uniform_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{ .binding = 0, .resource = .{ .Buffer = .{
                .size = @sizeOf(Uniforms),
                .offset = 0,
                .buffer = gizmo_uniform_buffer,
            } } },
        },
    });
    errdefer gizmo_uniform_bg.deinit();

    const voxels = try g.alloc.alloc(PackedVoxel, 64 * 64 * 64);
    @memset(voxels, PackedVoxel.air);
    voxels[32 * 64 * 64 + 32 * 64 + 32] = PackedVoxel.white;

    return .{
        .gizmo_pipeline_layout = gizmo_pipeline_layout,
        .gizmo_pipeline = gizmo_pipeline,
        .gizmo_vbo = gizmo_vbo,

        .gizmo_uniform_bg = gizmo_uniform_bg,
        .gizmo_uniform_buffer = gizmo_uniform_buffer,

        .voxels = voxels,
    };
}

pub fn deinit(self: Self) void {
    self.gizmo_pipeline_layout.deinit();
    self.gizmo_pipeline.deinit();
}

fn intersect(self: Self, pixel: [2]f32) ?Intersection {
    const dims = wgm.lossy_cast(f64, g.window.get_size() catch unreachable);
    const ray = blk: {
        var tmp = self.camera.create_ray_for_pixel(wgm.lossy_cast(f64, pixel), dims);
        tmp.origin = wgm.lossy_cast(f64, self.camera.global_coords);
        break :blk tmp;
    };

    const slab_res = rt.slab(f64, [2][3]f64{
        wgm.lossy_cast(f64, self.origin),
        wgm.add(wgm.lossy_cast(f64, self.origin), [_]f64{ 64, 64, 64 }),
    }, ray);
    std.log.debug("slab res: {any}", .{slab_res});
    std.log.debug("ray: {any}", .{ray});

    return undefined;
}

pub fn impl_thing_raw_event(self: *Self, ev: sdl.c.SDL_Event) !void {
    switch (ev.common.type) {
        sdl.c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            const event = ev.button;
            if (event.button == sdl.c.SDL_BUTTON_LEFT) {
                _ = self.intersect(.{ event.x, event.y });
            }
        },
        else => {},
    }
}

pub fn impl_thing_destroy(self: *Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn impl_thing_render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    const uniforms: Uniforms = .{
        .transform = wgm.lossy_cast(f32, self.camera.cached_global_transform),
    };
    g.queue.write_buffer(self.gizmo_uniform_buffer, 0, std.mem.asBytes(&uniforms));

    const cube_vertices = [_]GizmoVertex{
        .{ .pos = .{ 0, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 1, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 0, 1, 1 }, .color = undefined },

        .{ .pos = .{ 0, 1, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 1, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 1, 1 }, .color = undefined },

        .{ .pos = .{ 0, 1, 0, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 0, 1 }, .color = undefined },
        .{ .pos = .{ 0, 0, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 1, 1 }, .color = undefined },

        .{ .pos = .{ 0, 0, 1, 1 }, .color = undefined },
        .{ .pos = .{ 0, 1, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 0, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 0, 1 }, .color = undefined },

        .{ .pos = .{ 0, 1, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 0, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 1, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 0, 1 }, .color = undefined },
        .{ .pos = .{ 1, 1, 1, 1 }, .color = undefined },
    };

    const vertices = blk: {
        var ret = cube_vertices;
        for (ret, 0..) |v, i| {
            const o = wgm.add(
                wgm.swizzle(v.pos, "xyz"),
                wgm.lossy_cast(f32, self.origin),
            );
            ret[i].pos = .{ o[0], o[1], o[2], v.pos[3] };
            ret[i].color = .{ 255, 0, 255, 200 };
        }

        break :blk ret;
    };

    g.queue.write_buffer(self.gizmo_vbo, 0, std.mem.sliceAsBytes(&vertices));

    const render_pass = try encoder.begin_render_pass(.{
        .label = "gizmo render pass",
        .color_attachments = &.{.{
            .view = onto,
            .load_op = .Load,
            .store_op = .Store,
        }},
    });
    defer render_pass.deinit();
    defer render_pass.end();

    render_pass.set_pipeline(self.gizmo_pipeline);
    render_pass.set_bind_group(0, self.gizmo_uniform_bg, null);
    render_pass.set_vertex_buffer(0, self.gizmo_vbo, 0, vertices.len * @sizeOf(GizmoVertex));
    render_pass.draw(.{
        .first_vertex = 0,
        .vertex_count = vertices.len,
        .first_instance = 0,
        .instance_count = 1,
    });
}

pub fn impl_voxel_provider_draw(self: *Self, range: [2][3]isize, storage: []PackedVoxel) void {
    const info = VoxelProvider.overlap_info(range, .{
        self.origin,
        wgm.add(self.origin, [3]isize{ 64, 64, 64 }),
    }) orelse return;

    for (0..info.overlap_size[2]) |z| for (0..info.overlap_size[1]) |y| for (0..info.overlap_size[0]) |x| {
        const offset: [3]usize = .{ x, y, z };

        const ml_coords = wgm.add(info.model_origin, offset);
        const sample = self.voxels[ //
            ml_coords[2] * 64 * 64 //
            + ml_coords[1] * 64 //
            + ml_coords[0]
        ];

        const rl_coords = wgm.add(info.draw_origin, offset);
        storage[
            rl_coords[2] * info.range_size[1] * info.range_size[0] //
            + rl_coords[1] * info.range_size[0] //
            + rl_coords[0]
        ] = sample;
    };
}
