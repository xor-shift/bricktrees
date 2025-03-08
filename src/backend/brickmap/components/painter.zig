const std = @import("std");

const dyn = @import("dyn");
const wgm = @import("wgm");

const curves = @import("../bricktree/curves.zig");
const worker_pool = @import("../../../worker_pool.zig");

const PackedVoxel = @import("../../../voxel.zig").PackedVoxel;
const Voxel = @import("../../../voxel.zig").Voxel;

const IVoxelProvider = @import("../../../IVoxelProvider.zig");

const g = &@import("../../../main.zig").g;

pub fn Painter(comptime Cfg: type) type {
    return struct {
        const Self = @This();

        const Backend = @import("../backend.zig").Backend(Cfg);
        const Computer = @import("computer.zig").Computer(Cfg);
        const Storage = @import("storage.zig").Storage(Cfg);

        // const Storage = @import("Storage.zig");

        backend: *Backend = undefined,
        storage: *Storage = undefined,
        computer: *Computer = undefined,

        cached_origin: [3]isize = .{ 0, 0, 0 },
        cached_config: ?Backend.MapConfig = null,
        brickgrid_memo: []?usize = &.{},

        brickmap_gen_pool: *Pool,

        pub fn init() !Self {
            return .{
                .brickmap_gen_pool = try Pool.init(@min(std.Thread.getCpuCount() catch 1, 14), g.alloc, Self.pool_producer_fn, Self.pool_worker_fn),
            };
        }

        pub fn deinit(self: *Self) void {
            self.reconfigure(null) catch unreachable;
            self.brickmap_gen_pool.deinit();
            g.alloc.destroy(self.brickmap_gen_pool);
        }

        pub fn get_view_volume_for(origin_brickmap: [3]isize, grid_dimensions: [3]usize) [2][3]isize {
            return wgm.mulew([_][3]isize{
                wgm.cast(isize, origin_brickmap).?,
                wgm.add(origin_brickmap, wgm.cast(isize, grid_dimensions).?),
            }, Cfg.Brickmap.side_length_i);
        }

        /// Returns the minimum and the maximum global-voxel-coordinate of the view volume
        pub fn get_view_volume(self: Self) [2][3]isize {
            return get_view_volume_for(self.backend.origin_brickmap, self.backend.config.?.grid_dimensions);
        }

        pub fn sq_distance_to_center(self: Self, pt: [3]f64) f64 {
            const volume = wgm.lossy_cast(f64, self.get_view_volume());
            const center = wgm.div(wgm.add(volume[1], volume[0]), 2);
            const delta = wgm.sub(center, pt);
            return wgm.dot(delta, delta);
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

        fn find_slot(self: *Self, for_coords: [3]isize) ?usize {
            if (self.get_memo(for_coords)) |v| return v;

            for (self.backend.brickmap_tracker, 0..) |v, i| if (v == null) return i;

            return null;
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
            for (self.backend.brickmap_tracker, 0..) |maybe_abs, i| if (maybe_abs) |abs| {
                _ = self.set_memo(abs, i);
            };
        }

        fn reconfigure(self: *Self, config: ?Backend.MapConfig) !void {
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

        /// Returns the area (in brickmaps) that should be kept the same.
        fn recenter(self: *Self, origin: [3]isize) [2][3]isize {
            const old_volume = get_view_volume_for(self.cached_origin, self.backend.config.?.grid_dimensions);

            self.cached_origin = origin;

            const volume = self.get_view_volume();

            for (self.backend.brickmap_tracker, 0..) |v, i| if (v) |w| {
                const v_w = wgm.mulew(w, Cfg.Brickmap.side_length_i);
                if (wgm.compare(.all, v_w, .greater_than_equal, volume[0]) and //
                    wgm.compare(.all, v_w, .less_than, volume[1]))
                {
                    continue;
                }

                self.backend.brickmap_tracker[i] = null;
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

        pub fn render(self: *Self) !void {
            const voxel_providers: []dyn.Fat(*IVoxelProvider) = blk: {
                var list = std.ArrayList(dyn.Fat(*IVoxelProvider)).init(g.frame_alloc);

                var iter = g.thing_store.things.iterator();
                while (iter.next()) |thing| {
                    const vp = thing.value_ptr.sideways_cast(IVoxelProvider) orelse continue;
                    try list.append(vp);
                }

                break :blk try list.toOwnedSlice();
            };

            const redraw_everything = if (!std.meta.eql(self.cached_config, self.backend.config)) blk: {
                try self.reconfigure(self.backend.config);
                break :blk true;
            } else false;

            const already_drawn_range = if (!std.mem.eql(isize, &self.backend.origin_brickmap, &self.cached_origin))
                self.recenter(self.backend.origin_brickmap)
            else
                self.get_view_volume();

            for (voxel_providers) |p| {
                p.d("voxel_draw_start", .{});
            }

            defer for (voxel_providers) |p| {
                p.d("voxel_draw_end", .{});
            };

            var context: PoolContext = .{
                .self = self,
                .voxel_providers = voxel_providers,

                .curve = .{
                    .dims = self.backend.config.?.grid_dimensions,
                },

                .redraw_everything = redraw_everything,
                .already_drawn_range = already_drawn_range,
            };
            self.brickmap_gen_pool.begin_work(&context);

            while (self.brickmap_gen_pool.get_result()) |info| {
                const result = info.result;
                const absolute_bm_coords = info.for_work.brickmap_coords;

                const the_brickmap = &result.brickmap;
                const the_bricktree = &result.bricktree;

                if (result.is_empty) {
                    if (self.get_memo(absolute_bm_coords)) |slot| {
                        self.backend.brickmap_tracker[slot] = null;
                        _ = self.set_memo(absolute_bm_coords, null);
                    }
                } else if (self.find_slot(absolute_bm_coords)) |slot| {
                    self.backend.upload_brickmap(slot, the_brickmap, the_bricktree);
                    self.backend.brickmap_tracker[slot] = absolute_bm_coords;
                    _ = self.set_memo(absolute_bm_coords, slot);
                }
            }
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
            voxel_providers: []dyn.Fat(*IVoxelProvider) = &.{},

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
            brickmap: Cfg.Brickmap,
            bricktree: Cfg.BricktreeStorage,
        };

        const Pool = worker_pool.WorkerPool(PoolContext, PoolWork, PoolResult);

        fn should_draw(ctx: *PoolContext, range: [2][3]isize) bool {
            const should_draw_from_scratch = //
                ctx.redraw_everything or //
                wgm.compare(.some, range[0], .less_than, ctx.already_drawn_range[0]) or //
                wgm.compare(.some, range[1], .greater_than, ctx.already_drawn_range[1]);

            const someone_wants_to_draw = if (should_draw_from_scratch) blk: {
                for (ctx.voxel_providers) |p| {
                    if (p.d("should_draw_voxels", .{range})) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            const someone_wants_to_redraw = if (!should_draw_from_scratch) blk: {
                for (ctx.voxel_providers) |p| {
                    if (p.d("should_redraw_voxels", .{range})) {
                        break :blk true;
                    }
                }
                break :blk false;
            } else false;

            return someone_wants_to_redraw or someone_wants_to_draw;
        }

        fn pool_producer_fn(ctx: *PoolContext) ?PoolWork {
            while (true) {
                const vv_local_coords = ctx.curve.next() orelse return null;
                const abs_coords = wgm.add(wgm.cast(isize, vv_local_coords).?, ctx.self.backend.origin_brickmap);

                const voxel_coords = wgm.mulew(abs_coords, Cfg.Brickmap.side_length_i);
                const range = [_][3]isize{
                    voxel_coords,
                    wgm.add(voxel_coords, Cfg.Brickmap.side_length_i),
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

            for (ctx.voxel_providers) |p| {
                p.d("draw_voxels", .{ work.range, voxel_storage });
            }

            const as_brickmap: *Cfg.Brickmap = @ptrCast(voxel_storage.ptr);

            const is_empty = if (!Cfg.has_tree) blk: {
                break :blk std.mem.allEqual(u32, as_brickmap.c_flat_u32()[0..], 0);
            } else blk: {
                @memset(out_result.bricktree[0..], 0);
                Cfg.bricktree.make_tree_inplace(
                    Cfg.Brickmap.depth,
                    as_brickmap,
                    &out_result.bricktree,
                    switch (Cfg.curve_kind) {
                        .raster => curves.raster,
                        .llm1 => curves.llm,
                        .llm2 => @panic("unimplemented"),
                    },
                );

                break :blk out_result.bricktree[0] == 0;
            };

            out_result.is_empty = is_empty;
        }
    };
}
