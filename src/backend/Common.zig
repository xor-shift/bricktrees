const std = @import("std");

const wgpu = @import("gfx").wgpu;

const imgui = @import("imgui");
const wgm = @import("wgm");

const CameraThing = @import("../things/CameraThing.zig");
const VisualiserThing = @import("../things/VisualiserThing.zig");

const Uniforms = @import("uniforms.zig").Uniforms;

const g = &@import("../main.zig").g;

const Self = @This();

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

pub fn init() !Self {
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

    var ret: Self = .{
        .uniform_bgl = uniform_bgl,
        .uniform_bg = uniform_bg,
        .uniform_buffer = uniform_buffer,

        .rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64)),

        .compute_textures_bgl = compute_textures_bgl,
        .compute_textures_bg = .{},
    };

    try ret.resize(try g.window.get_size());

    return ret;
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

pub fn do_options_ui(self: *Self) void {
    _ = imgui.input_scalar(u32, "debug mode", &self.uniforms.debug_mode, 1, 1, .{});
    _ = imgui.input_scalar(u32, "debug level", &self.uniforms.debug_level, 1, 1, .{});
    _ = imgui.input_scalar(u32, "debug variable 0", &self.uniforms.debug_variable_0, 1, 1, .{});
    _ = imgui.input_scalar(u32, "debug variable 1", &self.uniforms.debug_variable_1, 1, 1, .{});
}

pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    _ = delta_ns;
    _ = encoder;
    _ = onto;

    const camera = g.get_thing("camera").?.get_concrete(CameraThing);

    self.rand.fill(std.mem.asBytes(&self.uniforms.random_seed));

    self.uniforms.transform = wgm.lossy_cast(f32, camera.cached_transform);
    self.uniforms.inverse_transform = wgm.lossy_cast(f32, camera.cached_transform_inverse);

    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&self.uniforms));
}
