const std = @import("std");

const blas = @import("blas/blas.zig");
const wgpu = @import("wgpu/wgpu.zig");

const Self = @This();

pub const chunk_dims = blas.vec3uz(64, 64, 64);
pub const height_in_chunks = 4;
pub const render_distance = blas.vec3uz(16, height_in_chunks, 16);

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
map_texture: wgpu.Texture,
map_texture_view: wgpu.TextureView,

chunk_mapping_texture: wgpu.Texture,
chunk_mapping_texture_view: wgpu.TextureView,
// visibility_texture: wgpu.Texture,
// visibility_texture_view: wgpu.TextureView,

pub fn init(alloc: std.mem.Allocator) !Self {
    const g_state = &@import("main.zig").g_state;

    const map_bgl = try g_state.device.create_bind_group_layout(.{
        .label = "compute map bgl",
        .entries = &.{
            .{
                .binding = 0,
                .visibility = .{
                    .compute = true,
                },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D2Array,
                    .multisampled = false,
                } },
            },
            .{
                .binding = 1,
                .visibility = .{
                    .compute = true,
                },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D3,
                    .multisampled = false,
                } },
            },
        },
    });

    const map_texture = try g_state.device.create_texture(.{
        .label = "map texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
            .storage_binding = true,
        },
        .dimension = .D2,
        .size = .{
            .width = @intCast(chunk_dims.x() * chunk_dims.z()),
            .height = @intCast(chunk_dims.y()),
            .depth_or_array_layers = 255,
        },
        .format = .R32Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });
    std.log.debug("compute map texture: {any}", .{map_texture});

    const map_texture_view = try map_texture.create_view(null);
    std.log.debug("compute map texture view: {any}", .{map_texture_view});

    const chunk_mapping_texture = try g_state.device.create_texture(.{
        .label = "chunk mapping texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .dimension = .D3,
        .size = .{
            .width = @intCast(render_distance.x()),
            .height = @intCast(render_distance.y()),
            .depth_or_array_layers = @intCast(render_distance.z()),
        },
        .format = .R8Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });

    const chunk_mapping_texture_view = try chunk_mapping_texture.create_view(null);

    const data_to_upload = try alloc.alloc(u8, render_distance.x() * render_distance.y() * render_distance.z() * 4);
    defer alloc.free(data_to_upload);
    @memset(data_to_upload, 0);
    data_to_upload[0 + 0 * render_distance.x() + 2 * render_distance.x() * render_distance.y()] = 1;
    data_to_upload[1 + 0 * render_distance.x() + 2 * render_distance.x() * render_distance.y()] = 1;

    g_state.queue.write_texture(.{
        .texture = chunk_mapping_texture,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
    }, data_to_upload, .{
        .width = @intCast(render_distance.x()),
        .height = @intCast(render_distance.y()),
        .depth_or_array_layers = @intCast(render_distance.z()),
    }, .{
        .offset = 0,
        .bytes_per_row = @intCast(render_distance.x()),
        .rows_per_image = @intCast(render_distance.y()),
    });

    const map_bg = try g_state.device.create_bind_group(.{
        .label = "compute map bind group",
        .layout = map_bgl,
        .entries = &.{
            .{
                .binding = 0,
                .resource = .{ .TextureView = map_texture_view },
            },
            .{
                .binding = 1,
                .resource = .{ .TextureView = chunk_mapping_texture_view },
            },
        },
    });

    var ret: Self = .{
        .map_bgl = map_bgl,
        .map_bg = map_bg,

        .map_texture = map_texture,
        .map_texture_view = map_texture_view,
        .chunk_mapping_texture = chunk_mapping_texture,
        .chunk_mapping_texture_view = chunk_mapping_texture_view,
    };

    try ret.generate_voxels(blas.vec3z(0, 0, 0), alloc);

    return ret;
}

fn generate_voxels(self: *Self, chunk_coords: blas.Vec3z, alloc: std.mem.Allocator) !void {
    const g_state = &@import("main.zig").g_state;

    const chunk_origin = blas.mulew(chunk_coords, chunk_dims.lossy_cast(isize));
    _ = chunk_origin;

    const data_to_upload = try alloc.alloc(u8, chunk_dims.x() * chunk_dims.y() * chunk_dims.z() * 4);
    @memset(data_to_upload, 0);
    defer alloc.free(data_to_upload);

    var xoshiro = std.rand.Xoshiro256.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
    const rand = xoshiro.random();
    _ = rand;

    const xyz_to_index = struct {
        fn aufruf(coords: [3]usize) usize {
            return coords[1] * chunk_dims.x() * chunk_dims.z() * 4 + //
                coords[2] * chunk_dims.x() * 4 + //
                coords[0] * 4;
        }
    }.aufruf;

    for (0..chunk_dims.x()) |x| for (0..chunk_dims.z()) |z| {
        const x_f = @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(chunk_dims.x()));
        const z_f = @as(f64, @floatFromInt(z)) / @as(f64, @floatFromInt(chunk_dims.z()));
        const dist = @sqrt(x_f * x_f + z_f * z_f);
        const theta = dist * 3.1415926535897932384626433 * 4;
        const height = 8 + @sin(theta) * 4.0;

        for (0..@as(usize, @intFromFloat(@trunc(height)))) |y| {
            const base_index = xyz_to_index(.{ x, y, z });

            data_to_upload[base_index] = 1;
        }

        // for (0..@min(x, z)) |y| {
        //     data_to_upload[xyz_to_index(.{ x, y, z })] = 1;
        // }
    };

    g_state.queue.write_texture(.{
        .texture = self.map_texture,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
    }, data_to_upload, .{
        .width = @intCast(chunk_dims.x() * chunk_dims.z()),
        .height = @intCast(chunk_dims.y()),
        .depth_or_array_layers = 1,
    }, .{
        .offset = 0,
        .bytes_per_row = @intCast(chunk_dims.x() * chunk_dims.z() * 4),
        .rows_per_image = @intCast(chunk_dims.y()),
    });
}
