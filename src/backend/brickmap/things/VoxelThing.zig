const std = @import("std");

const tracy = @import("tracy");
const wgm = @import("wgm");
const wgpu = @import("gfx").wgpu;

const curves = @import("../bricktree/curves.zig");
const worker_pool = @import("../../../worker_pool.zig");

const AnyThing = @import("../../../AnyThing.zig");

const PackedVoxel = @import("../../../voxel.zig").PackedVoxel;
const Voxel = @import("../../../voxel.zig").Voxel;

const MapThing = @import("MapThing.zig");
const CameraThing = @import("../../../things/CameraThing.zig");

const VoxelProvider = @import("../../../VoxelProvider.zig");

const g = &@import("../../../main.zig").g;

const Self = @This();

const VoxelProviderEntry = struct {
    provider: *VoxelProvider,
    last_acknowledged_update: u64,
};

const BrickgridEntry = struct {
    brickmap: u32,
};

const BrickmapEntry = struct {
    coords: [3]isize,
};

vtable_thing: AnyThing = AnyThing.mk_vtable(Self),

voxel_providers: std.ArrayList(?VoxelProviderEntry),

cached_config: ?MapThing.MapConfig = null,
cached_origin: [3]isize = .{0} ** 3,
brickgrid_memo: []?usize = &.{},

brickmap_gen_pool: *Pool,

map_thing: *MapThing = undefined,
camera_thing: *CameraThing = undefined,

pub fn init() !Self {
    return .{
        .voxel_providers = std.ArrayList(?VoxelProviderEntry).init(g.alloc),
        .brickmap_gen_pool = try Pool.init(@min(std.Thread.getCpuCount() catch 1, 14), g.alloc, Self.pool_producer_fn, Self.pool_worker_fn),
    };
}

pub fn deinit(self: *Self) void {
    self.brickmap_gen_pool.deinit();
    g.alloc.destroy(self.brickmap_gen_pool);
    self.voxel_providers.deinit();
    self.reconfigure(null) catch {};
}

pub fn add_voxel_provider(self: *Self, provider: *VoxelProvider) usize {
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

    const old_self = self;
    errdefer @panic("yeah");

    if (config) |v| {
        const new_memo = try g.alloc.alloc(?usize, v.grid_size());
        errdefer g.alloc.free(new_memo);
        @memset(new_memo, null);

        self.brickgrid_memo = new_memo;
    }

    if (old_self.cached_config != null) {
        g.alloc.free(self.brickgrid_memo);
    }
}

fn abs_to_memo(self: Self, abs_bm_coords: [3]isize) ?usize {
    const relative = wgm.cast(usize, wgm.sub(
        abs_bm_coords,
        self.cached_origin,
    )) orelse return null;

    const dims = self.cached_config.?.grid_dimensions;

    return relative[2] * dims[1] * dims[0] //
    + relative[1] * dims[0] //
    + relative[0]; //
}

fn set_memo(self: *Self, abs_bm_coords: [3]isize, val: ?usize) bool {
    self.brickgrid_memo[self.abs_to_memo(abs_bm_coords) orelse return false] = val;

    return true;
}

fn get_memo(self: Self, abs_bm_coords: [3]isize) ?usize {
    return self.brickgrid_memo[self.abs_to_memo(abs_bm_coords) orelse return null];
}

fn reconstruct_memo(self: *Self) void {
    @memset(self.brickgrid_memo, null);
    for (self.map_thing.brickmap_tracker, 0..) |maybe_abs, i| if (maybe_abs) |abs| {
        _ = self.set_memo(abs, i);
    };
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

    self.reconstruct_memo();

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

// fn coord_to_slot(self: Self, coords: [3]isize) ?usize {
// for (self.map_thing.brickmap_tracker, 0..) |v, i| if (v) |w| if (std.meta.eql(w, coords)) {
//     return i;
// };

// return null;
// }

fn find_slot(self: *Self, for_coords: [3]isize) ?usize {
    if (self.get_memo(for_coords)) |v| return v;

    for (self.map_thing.brickmap_tracker, 0..) |v, i| if (v == null) return i;

    return null;
}

const Curve = struct {
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

const PoolContext = struct {
    self: *Self,

    curve: Curve,

    redraw_everything: bool,
    already_drawn_range: [2][3]isize,
};

const PoolWork = struct {
    brickmap_coords: [3]isize,
    range: [2][3]isize,
};

const PoolResult = struct {
    is_empty: bool,
    brickmap: MapThing.Brickmap,
    bricktree: MapThing.BricktreeStorage,
};

const Pool = worker_pool.WorkerPool(PoolContext, PoolWork, PoolResult);

fn should_draw(ctx: *PoolContext, range: [2][3]isize) bool {
    const should_draw_from_scratch = //
        ctx.redraw_everything or //
        wgm.compare(.some, range[0], .less_than, ctx.already_drawn_range[0]) or //
        wgm.compare(.some, range[1], .greater_than, ctx.already_drawn_range[1]);

    const someone_wants_to_draw = if (should_draw_from_scratch) blk: {
        for (ctx.self.voxel_providers.items) |maybe_p| if (maybe_p) |p| {
            if (p.provider.should_draw(p.provider, range)) {
                break :blk true;
            }
        };
        break :blk false;
    } else false;

    const someone_wants_to_redraw = if (!should_draw_from_scratch) blk: {
        for (ctx.self.voxel_providers.items) |maybe_p| if (maybe_p) |p| {
            if (p.provider.should_redraw(p.provider, range)) {
                break :blk true;
            }
        };
        break :blk false;
    } else false;

    return someone_wants_to_redraw or someone_wants_to_draw;
}

fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
    while (true) {
        const vv_local_coords = ctx.curve.next() orelse return null;
        const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.cached_origin);

        const voxel_coords = wgm.mulew(abs_coords, MapThing.Brickmap.side_length_i);
        const range = [_][3]isize{
            voxel_coords,
            wgm.add(voxel_coords, MapThing.Brickmap.side_length_i),
        };

        if (!should_draw(ctx, range)) {
            continue;
        }

        return PoolWork{
            .brickmap_coords = abs_coords,
            .range = range,
        };
    }
}

fn pool_worker_fn(ctx: *PoolContext, out_result: *PoolResult, work: PoolWork) void {
    const voxel_storage = out_result.brickmap.flat()[0..];
    @memset(voxel_storage, std.mem.zeroes(PackedVoxel));

    for (ctx.self.voxel_providers.items) |maybe_p| if (maybe_p) |p| {
        p.provider.draw(p.provider, work.range, voxel_storage);
    };

    const as_brickmap: *MapThing.Brickmap = @ptrCast(voxel_storage.ptr);

    const is_empty = switch (@import("scene_config").scene_config) {
        .brickmap => std.mem.allEqual(u32, as_brickmap.c_flat_u32()[0..], 0),
        .brickmap_u64_bricktree, .brickmap_u8_bricktree => |v| blk: {
            @memset(out_result.bricktree[0..], 0);
            MapThing.bricktree.make_tree_inplace(MapThing.Brickmap.depth, as_brickmap, &out_result.bricktree, switch (v.curve_kind) {
                .raster => curves.raster,
                .last_layer_morton => curves.llm,
            });

            break :blk out_result.bricktree[0] == 0;
        },
    };

    out_result.is_empty = is_empty;
}

pub fn impl_thing_deinit(self: *Self) void {
    return self.deinit();
}

pub fn impl_thing_destroy(self: *Self, alloc: std.mem.Allocator) void {
    alloc.destroy(self);
}

pub fn impl_thing_render(self: *Self, _: u64, _: wgpu.CommandEncoder, _: wgpu.TextureView) !void {
    const redraw_everything = if (!std.meta.eql(self.cached_config, self.map_thing.config)) blk: {
        try self.reconfigure(self.map_thing.config);
        break :blk true;
    } else false;

    const already_drawn_range = if (!std.mem.eql(isize, &self.map_thing.origin_brickmap, &self.cached_origin))
        self.recenter(self.map_thing.origin_brickmap)
    else
        self.map_thing.get_view_volume();

    for (self.voxel_providers.items) |v| if (v) |w| {
        w.provider.render_start(w.provider);
    };

    defer for (self.voxel_providers.items) |v| if (v) |w| {
        w.provider.render_end(w.provider);
    };

    var context: PoolContext = .{
        .self = self,
        .curve = .{
            .dims = self.map_thing.config.?.grid_dimensions,
        },
        .redraw_everything = redraw_everything,
        .already_drawn_range = already_drawn_range,
    };
    self.brickmap_gen_pool.begin_work(&context);

    while (self.brickmap_gen_pool.get_result()) |info| {
        const result = info.result;
        const absolute_bm_coords = info.for_work.brickmap_coords;

        const brickmap = &result.brickmap;
        const bricktree = &result.bricktree;

        if (result.is_empty) {
            if (self.get_memo(absolute_bm_coords)) |slot| {
                self.map_thing.brickmap_tracker[slot] = null;
                _ = self.set_memo(absolute_bm_coords, null);
            }
        } else if (self.find_slot(absolute_bm_coords)) |slot| {
            self.map_thing.upload_brickmap(slot, brickmap, bricktree);
            self.map_thing.brickmap_tracker[slot] = absolute_bm_coords;
            _ = self.set_memo(absolute_bm_coords, slot);
        }
    }
}
