const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const wgpu = @import("gfx").wgpu;

const VisualiserThing = @import("../../things/VisualiserThing.zig");

const IBackend = @import("../IBackend.zig");
const IThing = @import("../../IThing.zig");
const IVoxelProvider = @import("../../IVoxelProvider.zig");

const Common = @import("../Common.zig");
const Uniforms = @import("../uniforms.zig").Uniforms;

const g = &@import("../../main.zig").g;

const Self = @This();

const Configuration = struct {
    depth: u6,
    batch_bpa: u6,
};

pub const DynStatic = dyn.ConcreteStuff(@This(), .{ IThing, IBackend });

common: Common,

compute_pipeline_layout: wgpu.PipelineLayout,
compute_pipeline: wgpu.ComputePipeline,

svo_bgl: wgpu.BindGroupLayout,
svo_bg: wgpu.BindGroup = .{},
svo_buffer: wgpu.Buffer = .{},

config: Configuration = .{
    .depth = 0,
    .batch_bpa = 3,
},
origin: [3]f64 = .{0} ** 3,

pub fn init() !*Self {
    const common = try Common.init();

    const compute_shader = try g.device.create_shader_module_wgsl_from_file("SVO shader", "shaders/svo.wgsl", g.alloc);
    errdefer compute_shader.deinit();

    const svo_bgl = try g.device.create_bind_group_layout(.{
        .label = "SVO bind group",
        .entries = &.{
            wgpu.BindGroupLayout.Entry{
                .binding = 0,
                .visibility = .{ .compute = true },
                .layout = .{
                    .Buffer = .{ .type = .ReadOnlyStorage },
                },
            },
        },
    });
    errdefer svo_bgl.deinit();

    const test_buffer: []const u32 = &.{
        0x0000FF00,
        0x00071717, // 11 10 10 00 00010111 17
        0x00062B2B, // 11 01 01 00 00101011 2B
        0x00054D4D, // 10 11 00 10 01001101 4D
        0x00048E8E, // 01 11 00 01 10001110 8E
        0x00037171, // 10 00 11 10 01110001 71
        0x0002B2B2, // 01 00 11 01 10110010 B2
        0x0001D4D4,
        0x0000E8E8,

        // at most 4 voxels in a group
        0xDEADBEEF,
        0xDEADBEEF,
        0xDEADBEEF,
        0xDEADBEEF,
    };

    const svo_buffer = try g.device.create_buffer(.{
        .label = "SVO buffer",
        .size = test_buffer.len * @sizeOf(u32),
        .usage = .{
            .copy_dst = true,
            .storage = true,
        },
        .mapped_at_creation = false,
    });
    errdefer svo_buffer.deinit();
    g.queue.write_buffer(svo_buffer, 0, std.mem.sliceAsBytes(test_buffer));

    const svo_bg = try g.device.create_bind_group(.{
        .label = "SVO bind group",
        .layout = svo_bgl,
        .entries = &.{
            wgpu.BindGroup.Entry{
                .binding = 0,
                .resource = .{ .Buffer = .{ .buffer = svo_buffer } },
            },
        },
    });
    errdefer svo_bg.deinit();

    const compute_pipeline_layout = try g.device.create_pipeline_layout(.{
        .label = "compute pipeline layout",
        .bind_group_layouts = &.{
            common.uniform_bgl,
            common.compute_textures_bgl,
            svo_bgl,
        },
    });
    errdefer compute_pipeline_layout.deinit();

    const compute_pipeline = try g.device.create_compute_pipeline(.{
        .label = "compute pipeline",
        .layout = compute_pipeline_layout,
        .compute = .{
            .module = compute_shader,
            .entry_point = "cs_main",
            .constants = &.{},
        },
    });
    errdefer compute_pipeline.deinit();

    const ret = try g.alloc.create(Self);
    ret.* = .{
        .common = common,

        .compute_pipeline_layout = compute_pipeline_layout,
        .compute_pipeline = compute_pipeline,

        .svo_bgl = svo_bgl,
        .svo_bg = svo_bg,
        .svo_buffer = svo_buffer,
    };

    try ret.configure(.{
        .desied_view_volume_size = .{1024} ** 3,
    });

    const dims = g.window.get_size() catch @panic("g.window.get_size()");
    try ret.resize(dims);

    return ret;
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn destroy(self: *Self, alloc: std.mem.Allocator) void {
    _ = self;
    _ = alloc;
}

pub fn resize(self: *Self, dims: [2]usize) !void {
    try self.common.resize(dims);
}

pub fn recenter(self: *Self, desired_center: [3]f64) void {
    _ = self;
    _ = desired_center;
}

pub fn view_volume(self: *Self) [2][3]isize {
    _ = self;
    return .{
        .{0} ** 3,
        .{0} ** 3,
    };
}

pub fn options_ui(self: *Self) void {
    self.common.do_options_ui();
}

pub fn get_origin(self: Self) [3]f64 {
    _ = self;
    return .{0} ** 3;
}

pub fn configure(self: *Self, config: IBackend.BackendConfig) anyerror!void {
    const batch_bpa: u6 = 3;
    const batch_sidelength = @as(usize, 1) << batch_bpa;

    const vvs = config.desied_view_volume_size;
    const max_sidelength = @max(@max(vvs[0], vvs[1]), vvs[2]);
    const aligned_sidelength = std.math.ceilPowerOfTwo(usize, max_sidelength) catch @panic("the hell are you doing???");
    const sidelength = @max(batch_sidelength, aligned_sidelength);
    const sidelength_log2: u6 = @intCast(@ctz(sidelength));

    const native_config: Configuration = .{
        .batch_bpa = batch_bpa,
        .depth = sidelength_log2,
    };

    try self.native_configure(native_config);
}

fn native_configure(self: *Self, config: Configuration) !void {
    _ = self;
    _ = config;
}

pub fn render(self: *Self, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
    try self.common.render(delta_ns, encoder, onto);

    const dims = g.window.get_size() catch @panic("g.window.get_size()");

    const compute_pass = try encoder.begin_compute_pass(.{
        .label = "svo compute pass",
    });

    compute_pass.set_pipeline(self.compute_pipeline);
    compute_pass.set_bind_group(0, self.common.uniform_bg, null);
    compute_pass.set_bind_group(1, self.common.compute_textures_bg, null);
    compute_pass.set_bind_group(2, self.svo_bg, null);

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

pub fn post_render(self: *Self) anyerror!void {
    _ = self;
}
