const std = @import("std");

const core = @import("core");
const wgm = @import("wgm");

const OBJFile = @import("qov").OBJFile;

pub fn voxelise_hw(alloc: std.mem.Allocator) !void {
    const wgpu = @import("gfx").wgpu;

    const instance = wgpu.Instance.init();
    defer instance.deinit();
    std.log.debug("instace: {any}", .{instance.handle});

    const adapter = try instance.request_adapter_sync(.{
        .backend_type = .Vulkan,
        .power_preference = .HighPerformance,
        .compatible_surface = .{},
    });
    defer adapter.deinit();
    std.log.debug("adapter: {any}", .{adapter.handle});

    const device = try adapter.request_device_sync(.{
        .label = "device",
        .default_queue = .{},
        .required_limits = .{},
        .required_features = &.{},
    });
    defer device.deinit();
    std.log.debug("device: {any}", .{device.handle});

    const dims: [3]usize = .{ 768, 768, 768 };
    const buffer = try device.create_texture(.{
        .label = "voxelisation target texture",
        .size = .{
            .width = @intCast(dims[0]),
            .height = @intCast(dims[1]),
            .depth_or_array_layers = @intCast(dims[2]),
        },
        .usage = .{
            .copy_src = true,
            .storage_binding = true,
        },
        .dimension = .D3,
        .format = .R32Uint,
        .sampleCount = 1,
        .mipLevelCount = 1,
        .view_formats = &.{},
    });
    defer buffer.deinit();

    const queue = try device.get_queue();
    defer queue.deinit();
    std.log.debug("queue: {any}", .{queue.handle});

    const pipeline_layout = try device.create_pipeline_layout(.{
        .label = "voxeliser compute pipeline layout",
        .bind_group_layouts = &.{},
    });
    defer pipeline_layout.deinit();
    std.log.debug("pipeline layout: {any}", .{pipeline_layout.handle});

    const shader = try device.create_shader_module_wgsl_from_file(
        "voxeliser compute shader",
        "shaders/voxeliser.wgsl",
        alloc,
    );
    defer shader.deinit();
    std.log.debug("shader: {any}", .{shader.handle});

    const pipeline = try device.create_compute_pipeline(.{
        .label = "voxeliser compute pipeline",
        .layout = pipeline_layout,
        .compute = .{
            .module = shader,
            .constants = &.{},
            .entry_point = "cs_main",
        },
    });
    defer pipeline.deinit();
    std.log.debug("pipeline: {any}", .{pipeline.handle});

    {
        const encoder = try device.create_command_encoder(.{
            .label = "voxelisation command encoder",
        });
        defer encoder.deinit();

        {
            const pass = try encoder.begin_compute_pass(.{
                .label = "voxelisation pass",
            });
            defer pass.deinit();

            pass.set_pipeline(pipeline);
            pass.dispatch_workgroups(.{ 13, 17, 23 });
            pass.end();
        }

        queue.submit(&.{
            try encoder.finish(null),
        });
    }
}

pub fn main() !void {}
