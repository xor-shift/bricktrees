const std = @import("std");

const blas = @import("blas/blas.zig");
const wgpu = @import("wgpu/wgpu.zig");

const Self = @This();

pub const Config = struct {
    no_chunks: usize,
    chunk_levels: usize,
    render_distance: blas.Vec3uz,

    pub fn chunk_dims(self: Config) blas.Vec3uz {
        return blas.explode(usize, 3, @as(usize, 1) << @as(u6, @intCast(self.chunk_levels)));
    }

    pub fn mipmap_texture_size(self: Config) usize {
        var no_elems: usize = 0;
        for (1..self.chunk_levels) |v| no_elems += std.math.pow(usize, 8, v);
        return no_elems / 8;
    }

    pub fn mipmap_index(self: Config, for_coords: blas.Vec3uz, for_level: usize) usize {
        std.debug.assert(for_level != 0);
        _ = self;
        _ = for_coords;
        return 0;
    }

    pub fn chunk_texture_bytes(self: Config) usize {
        const dims = self.chunk_dims();
        return dims.x() * dims.y() * dims.z() * 4;
    }

    pub fn chunk_texture_byte_index(self: Config, coords: blas.Vec3uz) usize {
        const dims = self.chunk_dims();
        return coords.y() * dims.x() * dims.z() * 4 + //
            coords.z() * dims.x() * 4 + //
            coords.x() * 4;
    }

    pub fn chunk_texture_size(self: Config) blas.Vec2uz {
        const dims = self.chunk_dims();

        return blas.vec2uz(
            dims.x() * dims.z(),
            dims.y(),
        );
    }
};

pub const config = Config{
    .no_chunks = 255,
    .chunk_levels = 6,
    .render_distance = blas.vec3uz(17, 4, 17),
};

map_bgl: wgpu.BindGroupLayout,
map_bg: wgpu.BindGroup,
map_texture: wgpu.Texture,
map_texture_view: wgpu.TextureView,
mipmap_texture: wgpu.Texture,
mipmap_texture_view: wgpu.TextureView,

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
                    .view_dimension = .D3,
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
                    .view_dimension = .D2,
                    .multisampled = false,
                } },
            },
            .{
                .binding = 2,
                .visibility = .{
                    .compute = true,
                },
                .layout = .{ .Texture = .{
                    .sample_type = .Uint,
                    .view_dimension = .D2Array,
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
            .width = @intCast(config.chunk_texture_size().width()),
            .height = @intCast(config.chunk_texture_size().height()),
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

    const mipmap_texture = try g_state.device.create_texture(.{
        .label = "mipmap texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
            .storage_binding = false,
        },
        .dimension = .D2,
        .size = .{
            .width = @intCast(config.mipmap_texture_size()),
            .height = @intCast(config.no_chunks),
            .depth_or_array_layers = 1,
        },
        .format = .R8Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });
    std.log.debug("compute mipmap texture: {any}", .{mipmap_texture});

    const mipmap_texture_view = try mipmap_texture.create_view(null);
    std.log.debug("compute mipmap texture view: {any}", .{mipmap_texture_view});

    const chunk_mapping_texture = try g_state.device.create_texture(.{
        .label = "chunk mapping texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .dimension = .D3,
        .size = .{
            .width = @intCast(config.render_distance.width()),
            .height = @intCast(config.render_distance.height()),
            .depth_or_array_layers = @intCast(config.render_distance.depth()),
        },
        .format = .R8Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });

    const chunk_mapping_texture_view = try chunk_mapping_texture.create_view(null);

    const data_to_upload = try alloc.alloc(u8, config.render_distance.width() * config.render_distance.height() * config.render_distance.depth() * 4);
    defer alloc.free(data_to_upload);
    @memset(data_to_upload, 0);
    data_to_upload[0] = 1;
    data_to_upload[2] = 1;

    g_state.queue.write_texture(.{
        .texture = chunk_mapping_texture,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
    }, data_to_upload, .{
        .width = @intCast(config.render_distance.x()),
        .height = @intCast(config.render_distance.y()),
        .depth_or_array_layers = @intCast(config.render_distance.z()),
    }, .{
        .offset = 0,
        .bytes_per_row = @intCast(config.render_distance.x()),
        .rows_per_image = @intCast(config.render_distance.y()),
    });

    const map_bg = try g_state.device.create_bind_group(.{
        .label = "compute map bind group",
        .layout = map_bgl,
        .entries = &.{
            .{
                .binding = 0,
                .resource = .{ .TextureView = chunk_mapping_texture_view },
            },
            .{
                .binding = 1,
                .resource = .{ .TextureView = mipmap_texture_view },
            },
            .{
                .binding = 2,
                .resource = .{ .TextureView = map_texture_view },
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
        .mipmap_texture = mipmap_texture,
        .mipmap_texture_view = mipmap_texture_view,
    };

    try ret.generate_voxels(blas.vec3z(0, 0, 0), alloc);

    return ret;
}

const ChunkInFlight = struct {
    voxels: []u32,
    mip: []u8,

    fn init(alloc: std.mem.Allocator) !ChunkInFlight {
        const dims = config.chunk_dims();

        const ret: ChunkInFlight = .{
            .voxels = try alloc.alloc(u32, dims.x() * dims.y() * dims.z()),
            .mip = try alloc.alloc(u8, config.mipmap_texture_size()),
        };
        @memset(ret.voxels, 0);
        @memset(ret.mip, 0);

        return ret;
    }

    fn upload_to_index(self: ChunkInFlight, map: Self, index: usize) void {
        const g_state = &@import("main.zig").g_state;

        g_state.queue.write_texture(.{
            .texture = map.map_texture,
            .origin = .{ .x = 0, .y = 0, .z = @intCast(index) },
        }, std.mem.sliceAsBytes(self.voxels), .{
            .width = @intCast(config.chunk_texture_size().width()),
            .height = @intCast(config.chunk_texture_size().height()),
            .depth_or_array_layers = 1,
        }, .{
            .offset = 0,
            .bytes_per_row = @intCast(config.chunk_texture_size().width() * 4),
            .rows_per_image = @intCast(config.chunk_texture_size().height()),
        });

        g_state.queue.write_texture(.{
            .texture = map.mipmap_texture,
            .origin = .{ .x = 0, .y = @intCast(index), .z = 0 },
        }, self.mip, .{
            .width = @intCast(config.mipmap_texture_size()),
            .height = 1,
            .depth_or_array_layers = 1,
        }, .{
            .offset = 0,
            .bytes_per_row = @intCast(config.mipmap_texture_size()),
            .rows_per_image = 1,
        });
    }

    fn set(self: *ChunkInFlight, local_coords: blas.Vec3uz, material: u32) void {
        const idx =
            local_coords.x() +
            local_coords.z() * config.chunk_dims().x() +
            local_coords.y() * (config.chunk_dims().x() * config.chunk_dims().z());

        self.voxels[idx] = material;

        var mip_offset: usize = 0;
        for (0..5) |i| {
            const shift = 5 - i;
            const x_bit = (local_coords.x() >> @as(u6, @intCast(shift))) & 1;
            const y_bit = (local_coords.y() >> @as(u6, @intCast(shift))) & 1;
            const z_bit = (local_coords.z() >> @as(u6, @intCast(shift))) & 1;

            const local_offset = (z_bit << 2) | (y_bit << 1) | x_bit;
            self.mip[mip_offset] |= @as(u8, 1) << @as(u3, @intCast(local_offset));

            mip_offset += (if (mip_offset == 0) 1 else @as(usize, 8) << @as(u6, @intCast(i))) + local_offset;
        }
    }
};

fn generate_voxels(self: *Self, chunk_coords: blas.Vec3z, alloc: std.mem.Allocator) !void {
    const chunk_origin = blas.mulew(chunk_coords, config.chunk_dims().lossy_cast(isize));
    _ = chunk_origin;

    var chunk = try ChunkInFlight.init(alloc);

    var xoshiro = std.rand.Xoshiro256.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
    const rand = xoshiro.random();
    _ = rand;

    for (0..config.chunk_dims().x()) |x| for (0..config.chunk_dims().z()) |z| {
        const x_f = @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(config.chunk_dims().x()));
        const z_f = @as(f64, @floatFromInt(z)) / @as(f64, @floatFromInt(config.chunk_dims().z()));
        const dist = @sqrt(x_f * x_f + z_f * z_f);
        const theta = dist * 3.1415926535897932384626433 * 4;
        const height = 8 + @sin(theta) * 4.0;

        for (0..@as(usize, @intFromFloat(@trunc(height)))) |y| {
            chunk.set(blas.vec3uz(x, y, z), 1);
        }
    };

    chunk.upload_to_index(self.*, 0);
}
