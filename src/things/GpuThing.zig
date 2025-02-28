const std = @import("std");

const mustache = @import("mustache");

const wgm = @import("wgm");
const imgui = @import("imgui");
const sdl = @import("gfx").sdl;
const wgpu = @import("gfx").wgpu;

const AnyThing = @import("../AnyThing.zig");

const MapThing = @import("MapThing.zig");
const VisualiserThing = @import("VisualiserThing.zig");

const TextureAndView = @import("gpu/TextureAndView.zig");

const Brickmap = MapThing.Brickmap;

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

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

    pub fn render(self_arg: *anyopaque, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(delta_ns, encoder, onto);
    }
};

// Be careful: the vecN<T> of WGSL and the [N]T of C/Zig may not have the same alignment!
const Uniforms = extern struct {
    random_seed: [8]u32 = .{0} ** 8,

    transform: [4][4]f32 = wgm.identity(f32, 4),
    inverse_transform: [4][4]f32 = wgm.identity(f32, 4),

    dims: [2]f32,
    debug_mode: u32 = 0,
    debug_level: u32 = 0,

    pos: [3]f32 = .{ 0, 0, 0 }, // redundant
    debug_variable_0: u32 = 0,

    brickgrid_origin: [3]i32 = .{0} ** 3,
    debug_variable_1: u32 = 0,
};

compute_shader: wgpu.ShaderModule,

rand: std.Random.Xoshiro256,
uniforms: Uniforms = .{
    .dims = .{
        @floatFromInt(@TypeOf(g.*).default_resolution[0]),
        @floatFromInt(@TypeOf(g.*).default_resolution[1]),
    },
},
uniform_buffer: wgpu.Buffer,
uniform_bgl: wgpu.BindGroupLayout,
uniform_bg: wgpu.BindGroup,

compute_textures_bgl: wgpu.BindGroupLayout,
compute_textures_bg: wgpu.BindGroup,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

map_thing: *MapThing = undefined,
visualiser: *VisualiserThing = undefined,

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

    std.log.debug("{any}", .{res});
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

pub fn init(map: *MapThing, alloc: std.mem.Allocator) !Self {
    const compute_shader = try make_shader(alloc);

    //const compute_shader = try g.device.create_shader_module_wgsl_from_file("compute shader", "shaders/compute.wgsl", alloc);
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

    const rand = std.Random.Xoshiro256.init(std.crypto.random.int(u64));

    var ret: Self = .{
        .compute_shader = compute_shader,

        .rand = rand,
        .uniform_bgl = uniform_bgl,
        .uniform_bg = uniform_bg,
        .uniform_buffer = uniform_buffer,

        .compute_textures_bgl = compute_textures_bgl,
        .compute_textures_bg = .{},

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,
    };
    errdefer ret.deinit();

    return ret;
}
pub fn deinit(self: *Self) void {
    self.compute_pipeline.deinit();
    self.compute_pipeline_layout.deinit();

    self.compute_textures_bg.deinit();
    self.compute_textures_bgl.deinit();
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn on_resize(self: *Self, dims: [2]usize) !void {
    self.uniforms.dims = .{
        @floatFromInt(dims[0]),
        @floatFromInt(dims[1]),
    };

    const compute_textures_bg = try g.device.create_bind_group(wgpu.BindGroup.Descriptor{
        .label = "compute textures' BG",
        .layout = self.compute_textures_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .TextureView = self.visualiser.visualisation_texture.view },
            },
        },
    });
    errdefer compute_textures_bg.deinit();

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
        _ = imgui.input_scalar(u32, "debug level", &self.uniforms.debug_level, 1, 1);
        _ = imgui.input_scalar(u32, "debug variable 0", &self.uniforms.debug_variable_0, 1, 1);
        _ = imgui.input_scalar(u32, "debug variable 1", &self.uniforms.debug_variable_1, 1, 1);
    }
    imgui.end();
}

pub fn render(self: *Self, _: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) !void {
    _ = onto;

    const dims = g.window.get_size() catch @panic("g.window.get_size()");

    self.rand.fill(std.mem.asBytes(&self.uniforms.random_seed));

    g.queue.write_buffer(self.uniform_buffer, 0, std.mem.asBytes(&self.uniforms));

    {
        const compute_pass = try encoder.begin_compute_pass(wgpu.ComputePass.Descriptor{
            .label = "compute pass",
        });

        compute_pass.set_pipeline(self.compute_pipeline);
        compute_pass.set_bind_group(0, self.uniform_bg, null);
        compute_pass.set_bind_group(1, self.compute_textures_bg, null);
        compute_pass.set_bind_group(2, self.map_thing.map_bg, null);

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
