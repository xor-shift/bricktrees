const std = @import("std");

const curves = @import("../bricktree/curves.zig");
const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const PackedVoxel = @import("../voxel.zig").PackedVoxel;
const Voxel = @import("../voxel.zig").Voxel;

const MapThing = @import("MapThing.zig");

const AnyThing = @import("../AnyThing.zig");
const VoxelProvider = @import("../VoxelProvider.zig");

const g = &@import("../main.zig").g;

const Self = @This();

pub const Any = struct {
    fn init(self: *Self) AnyThing {
        return .{
            .thing = @ptrCast(self),

            .deinit = Any.deinit,
            .destroy = Any.destroy,

            .on_tick = Any.on_tick,
            .render = Any.render,
        };
    }

    pub fn deinit(self_arg: *anyopaque) void {
        @as(*Self, @ptrCast(@alignCast(self_arg))).deinit();
    }

    pub fn destroy(self_arg: *anyopaque, on_alloc: std.mem.Allocator) void {
        on_alloc.destroy(@as(*Self, @ptrCast(@alignCast(self_arg))));
    }

    pub fn on_tick(self_arg: *anyopaque, delta_ns: u64) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).on_tick(delta_ns);
    }

    pub fn render(self_arg: *anyopaque, delta_ns: u64, encoder: wgpu.CommandEncoder, onto: wgpu.TextureView) anyerror!void {
        try @as(*Self, @ptrCast(@alignCast(self_arg))).render(delta_ns, encoder, onto);
    }
};

const VoxelProviderEntry = struct {
    provider: VoxelProvider,
    last_acknowledged_update: u64,
};

const BrickgridEntry = struct {
    brickmap: u32,
};

const BrickmapEntry = struct {
    coords: [3]isize,
};

voxel_providers: std.ArrayList(?VoxelProviderEntry),

cached_config: ?MapThing.MapConfig = null,
cached_origin: [3]isize = .{0} ** 3,

map_thing: *MapThing = undefined,

pub fn init() !Self {
    return .{
        .voxel_providers = std.ArrayList(?VoxelProviderEntry).init(g.alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.voxel_providers.deinit();
    self.reconfigure(null) catch {};
}

pub fn to_any(self: *Self) AnyThing {
    return Self.Any.init(self);
}

pub fn add_voxel_provider(self: *Self, provider: VoxelProvider) usize {
    const to_add: VoxelProviderEntry = .{
        .provider = provider,
        .last_acknowledged_update = 0,
    };

    for (self.voxel_providers.items, 0..) |v, i| if (v == null) {
        self.voxel_providers.items[i] = to_add;
        return i;
    };

    self.voxel_providers.append(to_add) catch @panic("OOM");
    return self.voxel_providers.items.len - 1;
}

fn on_tick(_: *Self, _: u64) !void {}

fn reconfigure(self: *Self, config: ?MapThing.MapConfig) !void {
    defer self.cached_config = config;
}

/// Returns the area (in brickmaps) that should be kept the same.
fn recenter(self: *Self, origin: [3]isize) [2][3]isize {
    const old_volume = MapThing.get_view_volume_for(self.cached_origin, self.map_thing.config.?.grid_dimensions);

    self.cached_origin = origin;

    const volume = self.map_thing.get_view_volume();

    for (self.map_thing.brickmap_tracker, 0..) |v, i| if (v) |w| {
        const v_w = wgm.mulew(w, MapThing.Brickmap.side_length_i);
        if (wgm.compare(.all, v_w, .greater_than_equal, volume[0]) and //
            wgm.compare(.all, v_w, .less_than, volume[1]))
        {
            continue;
        }

        self.map_thing.brickmap_tracker[i] = null;
    };

    return .{
        .{
            @max(old_volume[0][0], volume[0][0]),
            @max(old_volume[0][1], volume[0][1]),
            @max(old_volume[0][2], volume[0][2]),
        },
        .{
            @min(old_volume[1][0], volume[1][0]),
            @min(old_volume[1][1], volume[1][1]),
            @min(old_volume[1][2], volume[1][2]),
        },
    };
}

fn coord_to_slot(self: Self, coords: [3]isize) ?usize {
    for (self.map_thing.brickmap_tracker, 0..) |v, i| if (v) |w| if (std.meta.eql(w, coords)) {
        return i;
    };

    return null;
}

fn find_slot(self: *Self, for_coords: [3]isize) ?usize {
    if (self.coord_to_slot(for_coords)) |v| return v;

    for (self.map_thing.brickmap_tracker, 0..) |v, i| if (v == null) return i;

    return null;
}

fn render(self: *Self, _: u64, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    const redraw_everything = if (!std.meta.eql(self.cached_config, self.map_thing.config)) blk: {
        try self.reconfigure(self.map_thing.config);
        break :blk true;
    } else false;

    const already_drawn_range = if (!std.mem.eql(isize, &self.map_thing.origin_brickmap, &self.cached_origin))
        self.recenter(self.map_thing.origin_brickmap)
    else
        self.map_thing.get_view_volume();

    const Curve = struct {
        const Curve = @This();

        iteration: usize = 0,
        dims: [3]usize,

        fn next(ctx: *Curve) ?[3]usize {
            const z = ctx.iteration / (ctx.dims[1] * ctx.dims[0]);
            const y = (ctx.iteration / ctx.dims[0]) % ctx.dims[1];
            const x = ctx.iteration % ctx.dims[0];

            if (z >= ctx.dims[2]) return null;

            ctx.iteration += 1;

            return .{ x, y, z };
        }
    };

    for (self.voxel_providers.items) |v| if (v) |w| {
        w.provider.render_start(w.provider.provider);
    };

    defer for (self.voxel_providers.items) |v| if (v) |w| {
        w.provider.render_end(w.provider.provider);
    };

    const voxel_storage = try g.frame_alloc.alloc(PackedVoxel, MapThing.Brickmap.volume);
    const tree_storage = try g.frame_alloc.create(MapThing.BricktreeStorage);

    var curve: Curve = .{ .dims = self.map_thing.config.?.grid_dimensions };
    while (curve.next()) |vv_local_coords| {
        const absolute_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, self.cached_origin);

        const voxel_coords = wgm.mulew(absolute_coords, MapThing.Brickmap.side_length_i);
        const range = [_][3]isize{
            voxel_coords,
            wgm.add(voxel_coords, MapThing.Brickmap.side_length_i),
        };

        const should_redaw_anyway = //
            redraw_everything or //
            wgm.compare(.some, range[0], .less_than, already_drawn_range[0]) or //
            wgm.compare(.some, range[1], .greater_than, already_drawn_range[1]);

        const someone_wants_to_redraw = if (!should_redaw_anyway) blk: {
            for (self.voxel_providers.items) |maybe_p| if (maybe_p) |p| {
                if (p.provider.should_redraw(p.provider.provider, range)) {
                    break :blk true;
                }
            };
            break :blk false;
        } else false;

        const should_redaw = someone_wants_to_redraw or should_redaw_anyway;

        if (!should_redaw) continue;

        @memset(voxel_storage, std.mem.zeroes(PackedVoxel));

        for (self.voxel_providers.items) |maybe_p| if (maybe_p) |p| {
            p.provider.draw(p.provider.provider, range, voxel_storage);
        };

        const as_brickmap: *MapThing.Brickmap = @ptrCast(voxel_storage.ptr);

        const is_empty = switch (@import("scene_config").scene_config) {
            .brickmap => std.mem.allEqual(u32, as_brickmap.c_flat_u32()[0..], 0),
            .brickmap_u64_bricktree, .brickmap_u8_bricktree => |v| blk: {
                @memset(tree_storage.*[0..], 0);
                MapThing.bricktree.make_tree_inplace(MapThing.Brickmap.depth, as_brickmap, tree_storage, switch (v.curve_kind) {
                    .raster => curves.raster,
                    .last_layer_morton => curves.llm,
                });

                break :blk tree_storage[0] == 0;
            },
        };

        if (is_empty) {
            if (self.coord_to_slot(absolute_coords)) |v| {
                self.map_thing.brickmap_tracker[v] = null;
            }

            continue;
        }

        const slot = if (self.find_slot(absolute_coords)) |v| v else break;

        // std.log.debug("[{d}] = {any}", .{slot, absolute_coords});
        self.map_thing.upload_brickmap(slot, as_brickmap, tree_storage);
        self.map_thing.brickmap_tracker[slot] = absolute_coords;
    }
}
