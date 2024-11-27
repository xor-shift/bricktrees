const std = @import("std");

const blas = @import("blas/blas.zig");
const wgpu = @import("wgpu/wgpu.zig");

const Self = @This();

const constants = struct {
    sentinel_chunk_id: usize = 255,
    no_chunks: usize = 255,
    chunk_dims: blas.Vec3uz = blas.vec3uz(64, 64, 64),
    height: usize = 4,
}{};

const GPUChunk = struct {
    const chunk_texture_dims = blas.vec2uz(64 * 64, 64);

    coords: blas.Vec3z,
    invalidated: bool = false,

    voxels: []u32 = &.{},
    mip: []u8 = &.{},

    fn mipmap_indices(coords: blas.Vec3uz) [5]usize {
        var ret: [5]usize = undefined;

        var mip_offset: usize = 0;
        for (0..5) |i| {
            const shift = 5 - i;

            const level_x = (coords.x() >> @as(u6, @intCast(shift)));
            const level_y = (coords.y() >> @as(u6, @intCast(shift)));
            const level_z = (coords.z() >> @as(u6, @intCast(shift)));

            const level_offset =
                (level_z << @as(u6, @intCast((i + 1) * 2))) |
                (level_y << @as(u6, @intCast(i + 1))) |
                level_x;

            ret[i] = mip_offset + level_offset;

            const local_mip_offset = @as(usize, 1) << @as(u6, @intCast(i * 3 + 3));

            mip_offset += local_mip_offset;
        }

        return ret;
    }

    pub fn get_mipmap_texture_size() usize {
        var no_elems: usize = 0;
        for (1..6) |v| no_elems += std.math.pow(usize, 8, v);
        return no_elems / 8;
    }

    const mipmap_texture_size = get_mipmap_texture_size();

    fn create_chunk_store_texture() wgpu.Error!wgpu.Texture {
        const g_state = &@import("main.zig").g_state;
        return try g_state.device.create_texture(.{
            .label = "chunk store texture for chunk type 0",
            .usage = .{
                .copy_dst = true,
                .texture_binding = true,
            },
            .dimension = .D2,
            .size = .{
                .width = @intCast(chunk_texture_dims.width()),
                .height = @intCast(chunk_texture_dims.height()),
                .depth_or_array_layers = constants.no_chunks,
            },
            .format = .R32Uint,
            .mipLevelCount = 1,
            .sampleCount = 1,
            .view_formats = &.{},
        });
    }

    fn create_mipmap_store_texture() wgpu.Error!wgpu.Texture {
        const g_state = &@import("main.zig").g_state;
        return try g_state.device.create_texture(.{
            .label = "mipmap texture",
            .usage = .{
                .copy_dst = true,
                .texture_binding = true,
                .storage_binding = false,
            },
            .dimension = .D2,
            .size = .{
                .width = @intCast(mipmap_texture_size),
                .height = @intCast(constants.no_chunks),
                .depth_or_array_layers = 1,
            },
            .format = .R8Uint,
            .mipLevelCount = 1,
            .sampleCount = 1,
            .view_formats = &.{},
        });
    }

    fn deinit(self: GPUChunk, alloc: std.mem.Allocator) void {
        alloc.free(self.voxels);
        alloc.free(self.mip);
    }

    fn init(alloc: std.mem.Allocator, global_chunk_coord: blas.Vec3z) !GPUChunk {
        const ret: GPUChunk = .{
            .coords = global_chunk_coord,
            .invalidated = false,
            .voxels = try alloc.alloc(u32, blas.reduce(constants.chunk_dims, .Mul)),
            .mip = try alloc.alloc(u8, mipmap_texture_size),
        };
        @memset(ret.voxels, 0);
        @memset(ret.mip, 0);

        return ret;
    }

    fn upload_to_index(self: *GPUChunk, map: Self, index: usize) void {
        const g_state = &@import("main.zig").g_state;

        g_state.queue.write_texture(.{
            .texture = map.chunk_store_texture,
            .origin = .{ .x = 0, .y = 0, .z = @intCast(index) },
        }, std.mem.sliceAsBytes(self.voxels), .{
            .width = @intCast(chunk_texture_dims.width()),
            .height = @intCast(chunk_texture_dims.height()),
            .depth_or_array_layers = 1,
        }, .{
            .offset = 0,
            .bytes_per_row = @intCast(chunk_texture_dims.width() * 4),
            .rows_per_image = @intCast(chunk_texture_dims.height()),
        });

        g_state.queue.write_texture(.{
            .texture = map.mipmap_store_texture,
            .origin = .{ .x = 0, .y = @intCast(index), .z = 0 },
        }, self.mip, .{
            .width = @intCast(mipmap_texture_size),
            .height = 1,
            .depth_or_array_layers = 1,
        }, .{
            .offset = 0,
            .bytes_per_row = @intCast(mipmap_texture_size),
            .rows_per_image = 1,
        });

        self.invalidated = false;
    }

    fn set(self: *GPUChunk, local_coords: blas.Vec3uz, material: u32) void {
        self.invalidated = true;

        const idx =
            local_coords.x() +
            local_coords.z() * constants.chunk_dims.x() +
            local_coords.y() * (constants.chunk_dims.x() * constants.chunk_dims.z());

        self.voxels[idx] = material;

        for (mipmap_indices(local_coords)) |level_offset| {
            const byte_offset = level_offset / 8;
            const bit_offset = @as(u3, @intCast(level_offset % 8));

            // std.log.debug("setting byte {d}, bit {d}", .{ byte_offset, bit_offset });

            self.mip[byte_offset] |= @as(u8, 1) << bit_offset;
        }
    }
};

test "mipmap indices" {
    const table = [_]std.meta.Tuple(&.{ blas.Vec3uz, [5]usize }){
        .{ blas.vec3uz(0, 0, 0), [5]usize{ 0, 1, 9, 73, 585 } },
        .{ blas.vec3uz(2, 0, 0), [5]usize{ 0, 1, 9, 73, 586 } },
    };

    for (0.., table) |i, test_pair| {
        const coords = test_pair.@"0";
        const expected = test_pair.@"1";
        const got = GPUChunk.mipmap_indices(coords);
        if (!std.mem.eql(usize, &expected, &got)) {
            std.log.err("test #{d}, coordinates ({d}, {d}, {d}): expected: {any}, got: {any}", .{
                i,        coords.x(), coords.y(), coords.z(),
                expected, got,
            });
        }
    }
}

const Chunkmap = struct {
    origin: blas.Vec3z,
    size: blas.Vec3uz,

    texture: wgpu.Texture,
};

alloc: std.mem.Allocator,

map_bgl: wgpu.BindGroupLayout,

mipmap_store_texture: wgpu.Texture,
mipmap_store_texture_view: wgpu.TextureView,
chunk_store_texture: wgpu.Texture,
chunk_store_texture_view: wgpu.TextureView,

stored_chunks: []?GPUChunk,

render_distance: usize = 0,
origin_chunk: blas.Vec2z = blas.vec2z(0, 0),

chunkmap_invalidated: bool = false,
local_chunkmap: []u16 = undefined,

chunkmap_texture: wgpu.Texture = .{},
chunkmap_texture_view: wgpu.TextureView = .{},
map_bg: wgpu.BindGroup = .{},

fn get_chunkmap_dimensions(render_distance: usize) blas.Vec3uz {
    const sidelength = render_distance * 2 + 1;
    return blas.vec3uz(sidelength, constants.height, sidelength);
}

fn get_chunkmap_min_max(self: Self) [2]blas.Vec3z {
    return [2]blas.Vec3z{
        blas.vec3z(
            self.origin_chunk.x() - @as(isize, @intCast(self.render_distance)),
            0,
            self.origin_chunk.y() - @as(isize, @intCast(self.render_distance)),
        ),
        blas.vec3z(
            self.origin_chunk.x() + @as(isize, @intCast(self.render_distance)),
            constants.height,
            self.origin_chunk.y() + @as(isize, @intCast(self.render_distance)),
        ),
    };
}

fn get_chunkmap_local_chunk_coordinates(self: Self, chunk_coords: blas.Vec3z) ?blas.Vec3uz {
    const minmax = self.get_chunkmap_min_max();
    const min = minmax[0];
    const max = minmax[1];

    _ = max;

    // TODO: check for bounds
    const candidate = blas.sub(chunk_coords, min);

    return candidate.lossy_cast(usize);
}

pub fn set_position(self: *Self, position: blas.Vec3d) !void {
    _ = self;
    _ = position;
}

pub fn set_render_distance(self: *Self, render_distance: usize) !void {
    const g_state = &@import("main.zig").g_state;

    if (self.render_distance != 0) {
        self.alloc.free(self.local_chunkmap);
        self.local_chunkmap = undefined;

        self.chunkmap_texture.release();
        self.chunkmap_texture = .{};
        self.chunkmap_texture_view.release();
        self.chunkmap_texture_view = .{};
        self.map_bg.release();
        self.map_bg = .{};
    }

    if (render_distance == 0) {
        self.render_distance = 0;
        return;
    }

    const dimensions = get_chunkmap_dimensions(render_distance);

    self.local_chunkmap = try self.alloc.alloc(u16, blas.reduce(dimensions, .Mul));
    @memset(self.local_chunkmap, constants.sentinel_chunk_id);

    const chunkmap_texture = try g_state.device.create_texture(.{
        .label = "chunk mapping texture",
        .usage = .{
            .copy_dst = true,
            .texture_binding = true,
        },
        .dimension = .D3,
        .size = .{
            .width = @intCast(dimensions.width()),
            .height = @intCast(dimensions.height()),
            .depth_or_array_layers = @intCast(dimensions.depth()),
        },
        .format = .R16Uint,
        .mipLevelCount = 1,
        .sampleCount = 1,
        .view_formats = &.{},
    });
    defer self.chunkmap_texture = chunkmap_texture;

    const chunkmap_texture_view = try chunkmap_texture.create_view(null);
    defer self.chunkmap_texture_view = chunkmap_texture_view;

    self.map_bg = try g_state.device.create_bind_group(.{
        .label = "compute map bind group",
        .layout = self.map_bgl,
        .entries = &.{
            .{
                .binding = 0,
                .resource = .{ .TextureView = chunkmap_texture_view },
            },
            .{
                .binding = 1,
                .resource = .{ .TextureView = self.mipmap_store_texture_view },
            },
            .{
                .binding = 2,
                .resource = .{ .TextureView = self.chunk_store_texture_view },
            },
        },
    });

    self.render_distance = render_distance;
}

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

    const chunk_store_texture = try GPUChunk.create_chunk_store_texture();
    std.log.debug("chunk store texture texture: {any}", .{chunk_store_texture});

    const chunk_store_texture_view = try chunk_store_texture.create_view(null);
    std.log.debug("view for the chunk store texture: {any}", .{chunk_store_texture_view});

    const mipmap_store_texture = try GPUChunk.create_mipmap_store_texture();
    std.log.debug("mipmap store texture: {any}", .{mipmap_store_texture});

    const mipmap_store_texture_view = try mipmap_store_texture.create_view(null);
    std.log.debug("view for the mipmap store texture: {any}", .{mipmap_store_texture_view});

    var ret: Self = .{
        .alloc = alloc,

        .map_bgl = map_bgl,

        .mipmap_store_texture = mipmap_store_texture,
        .mipmap_store_texture_view = mipmap_store_texture_view,
        .chunk_store_texture = chunk_store_texture,
        .chunk_store_texture_view = chunk_store_texture_view,

        .stored_chunks = try alloc.alloc(?GPUChunk, constants.no_chunks),
    };

    @memset(ret.stored_chunks, null);

    try ret.set_render_distance(4);
    try ret.set_position(blas.vec3d(0, 0, 0));

    for (0..6) |z| for (0..6) |x| {
        try ret.generate_voxels(blas.vec3z(
            @as(isize, @intCast(x)) - 3,
            0,
            @as(isize, @intCast(z)) - 3,
        ));
    };

    return ret;
}

pub fn deinit(self: *Self) void {
    self.set_render_distance(0) catch unreachable;
    for (self.stored_chunks) |v| if (v) |w| w.deinit(self.alloc);
    self.alloc.free(self.stored_chunks);
}

fn upload_chunkmap(self: *Self) void {
    const g_state = &@import("main.zig").g_state;

    const dimensions = get_chunkmap_dimensions(self.render_distance);

    self.chunkmap_invalidated = false;

    g_state.queue.write_texture(.{
        .texture = self.chunkmap_texture,
        .origin = .{ .x = 0, .y = 0, .z = 0 },
    }, std.mem.sliceAsBytes(self.local_chunkmap), .{
        .width = @intCast(dimensions.x()),
        .height = @intCast(dimensions.y()),
        .depth_or_array_layers = @intCast(dimensions.z()),
    }, .{
        .offset = 0,
        .bytes_per_row = @intCast(dimensions.x() * 2),
        .rows_per_image = @intCast(dimensions.y()),
    });
}

fn chunkmap_set_index(self: *Self, cml_chunk_coords: blas.Vec3uz, index: usize) void {
    const v = cml_chunk_coords; // short name
    const dims = get_chunkmap_dimensions(self.render_distance);

    self.chunkmap_invalidated = true;
    self.local_chunkmap[v.x() + v.y() * dims.x() + v.z() * (dims.x() * dims.y())] = @intCast(index);
}

fn generate_voxels(self: *Self, chunk_coords: blas.Vec3z) !void {
    const index: usize = val: {
        for (0.., self.stored_chunks) |i, v| {
            // std.log.debug("chunk #{d}: {any}", .{ i, v });
            if (v != null) continue;
            break :val i;
        }

        std.log.warn("no empty spot was found for the chunk {d}, {d}, {d}", .{
            chunk_coords.x(),
            chunk_coords.y(),
            chunk_coords.z(),
        });

        return;
    };

    const cml_chunk_coords = self.get_chunkmap_local_chunk_coordinates(chunk_coords) orelse {
        std.log.warn("chunk {d}, {d}, {d} was out of bounds", .{
            chunk_coords.x(),
            chunk_coords.y(),
            chunk_coords.z(),
        });
        return;
    };

    std.log.debug("going to upload the chunk at {d}, {d}, {d} to index {d} with chunkmap-local coordinates: {d}, {d}, {d}", .{
        chunk_coords.x(),
        chunk_coords.y(),
        chunk_coords.z(),
        index,
        cml_chunk_coords.x(),
        cml_chunk_coords.y(),
        cml_chunk_coords.z(),
    });

    const chunk_origin = blas.mulew(chunk_coords, constants.chunk_dims.lossy_cast(isize));

    var chunk = try GPUChunk.init(self.alloc, chunk_coords);

    var xoshiro = std.rand.Xoshiro256.init(@truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
    const rand = xoshiro.random();
    _ = rand;

    // chunk.set(blas.vec3uz(7, 7, 7), 1);

    for (0..constants.chunk_dims.x()) |x| for (0..constants.chunk_dims.z()) |z| {
        const x_f = @as(f64, @floatFromInt(chunk_origin.x() + @as(i32, @intCast(x)))) / @as(f64, @floatFromInt(constants.chunk_dims.x()));
        const z_f = @as(f64, @floatFromInt(chunk_origin.z() + @as(i32, @intCast(z)))) / @as(f64, @floatFromInt(constants.chunk_dims.z()));
        const dist = @sqrt(x_f * x_f + z_f * z_f);
        const theta = dist * 3.1415926535897932384626433 * 4;
        const height = 8 + @sin(theta) * 4.0 + dist * 6.0;

        for (0..@as(usize, @intFromFloat(@trunc(height)))) |y| {
            chunk.set(blas.vec3uz(x, y, z), 1);
        }
    };

    self.stored_chunks[index] = chunk;
    self.chunkmap_set_index(cml_chunk_coords, index);
}

pub fn pre_frame(self: *Self, ms_spent_last_frame: f64) void {
    _ = ms_spent_last_frame;

    for (0..self.stored_chunks.len) |i| {
        if (self.stored_chunks[i] == null) continue;

        const chunk = &self.stored_chunks[i].?;

        if (!chunk.invalidated) continue;

        std.log.info("chunk #{d} at global coords {d}, {d}, {d} was invalidated, uploading anew", .{
            i,
            chunk.coords.x(),
            chunk.coords.y(),
            chunk.coords.z(),
        });

        chunk.upload_to_index(self.*, i);
    }

    if (self.chunkmap_invalidated) {
        std.log.info("chunkmap was invalidated, uploading anew", .{});
        self.upload_chunkmap();
    }
}
